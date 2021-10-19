/*
 * id-updater
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 *
 */

#include "idupdater.h"

#include "common/Common.h"
#include "common/Configuration.h"
#include "common/QPCSC.h"

#include <QDebug>
#include <QDir>
#include <QElapsedTimer>
#include <QJsonArray>
#include <QJsonObject>
#include <QNetworkReply>
#include <QProcess>
#include <QPushButton>
#include <QSettings>
#include <QScopedPointer>
#include <QSslCertificate>
#include <QUrl>

#include <qt_windows.h>
#include <Msi.h>
#include <Softpub.h>

idupdaterui::idupdaterui( const QString &version, idupdater *parent )
:	QWidget()
{
	setupUi( this );
	m_message->hide();
	connect( parent, &idupdater::status, m_updateStatus, &QLabel::setText );
	connect( parent, &idupdater::message, m_message, [this](const QString &msg) {
		m_message->setHidden(msg.isEmpty());
		m_message->setText(msg);
	});
	connect( parent, &idupdater::error, this, &idupdaterui::setError );
	connect( buttonBox, &QDialogButtonBox::accepted, parent, &idupdater::startInstall );
	connect( buttonBox,  &QDialogButtonBox::rejected, qApp, &QCoreApplication::quit );
	buttonBox->button( QDialogButtonBox::Ok )->setText( tr("Start downloading") );
	buttonBox->button( QDialogButtonBox::Close )->setText( tr("Close") );
	setDownloadEnabled( false );
	m_installedVer->setText( version );
	show();
}

void idupdaterui::setDownloadEnabled( bool enabled )
{
	availableVerLabel->setVisible( enabled );
	m_availableVer->setVisible( enabled );
	m_downloadProgress->setVisible( enabled );
	buttonBox->button( QDialogButtonBox::Ok )->setEnabled( enabled );
}

void idupdaterui::setError( const QString &msg )
{
	m_updateStatus->setText( idupdater::tr("Failed: ") + msg );
}

void idupdaterui::setInfo( const QString &version, const QString &available )
{
	setDownloadEnabled( idupdater::lessThanVersion( version, available ) );
	m_installedVer->setText( version );
	m_availableVer->setText( available );
}

void idupdaterui::setProgress( QNetworkReply *reply )
{
	buttonBox->button( QDialogButtonBox::Ok )->setEnabled( false );
	m_downloadProgress->setValue( 0 );
	connect( reply, &QNetworkReply::downloadProgress, this, [&]( qint64 recvd, qint64 total ) {
		static QElapsedTimer timer;
		static qint64 lastRecvd = 0;
		if( timer.hasExpired( 1000 ) )
		{
			m_downloadStatus->setText( QString( "%1 KB/s" ).arg( (recvd - lastRecvd) / timer.elapsed() ) );
			lastRecvd = recvd;
			timer.restart();
		}
		m_downloadProgress->setMaximum( total );
		m_downloadProgress->setValue( recvd );
	});
}



idupdater::idupdater( QObject *parent )
	: QNetworkAccessManager( parent )
	, version(installedVersion("{f1c4d351-269d-4bee-8cdb-6ea70c968875}"))
{
	QLocale::Language language = QLocale::system().language();
	QString locale = language == QLocale::C ? "English/United States" : QLocale::languageToString( language );
	CPINFOEX CPInfoEx = {};
	if( GetCPInfoExW( GetConsoleCP(), 0, &CPInfoEx ) != 0 )
		locale += QStringLiteral(" / ") + QString::fromWCharArray(CPInfoEx.CodePageName);
	QString userAgent = QStringLiteral( "%1/%2 (%3) Locale: %4 Devices: %5")
		.arg(qApp->applicationName(), version, Common::applicationOs(), locale, QPCSC::instance().drivers().join("/"));
	qDebug() << "User-Agent:" << userAgent;
	request.setRawHeader( "User-Agent", userAgent.toUtf8() );
	connect( this, &QNetworkAccessManager::finished, this, &idupdater::reply );
	connect(&Configuration::instance(), &Configuration::finished, this, &idupdater::finished);
}

void idupdater::reply( QNetworkReply *reply )
{
	if(reply->error() != QNetworkReply::NoError)
	{
		emit error(reply->errorString());
		return reply->deleteLater();
	}

	qDebug() << "Downloaded" << reply->url().toString();
	emit status(tr("Download finished, starting installation..."));
	QFile tmp(QDir::tempPath() + "/" + reply->url().fileName());
	if(!tmp.open(QFile::WriteOnly))
		return emit error(tr("Downloaded package integrity check failed"));

	tmp.write(reply->readAll());
	tmp.close();
	reply->deleteLater();

	bool verify = verifyPackage(tmp.fileName());
	qDebug() << "Package signature" << (verify ? "OK" : "NOT OK");
	if(!verify)
		return emit error( tr("Downloaded package integrity check failed") );
	if(!QProcess::startDetached( tmp.fileName(),
			m_autoupdate ? QStringList("/quiet") : QStringList()))
		return emit error( tr("Package installation failed"));
	emit status(tr("Package installed"));
	QApplication::quit();
}

void idupdater::checkUpdates(bool autoupdate, bool autoclose)
{
	m_autoupdate = autoupdate;
	m_autoclose = autoclose;
	if(!autoclose && !w)
	{
		w = new idupdaterui(version, this);
		request.setRawHeader("User-Agent", request.rawHeader( "User-Agent" ) + " manual");
	}
	emit status(tr("Checking for update.."));
	Configuration::instance().update();
}

void idupdater::finished(bool /*changed*/, const QString &err)
{
	if(!err.isEmpty())
		return emit error(err);

	emit status(tr("Check completed"));

	QJsonObject obj = Configuration::instance().object();
	if(obj.contains("WIN-MESSAGE"))
		emit message(obj.value("WIN-MESSAGE").toString());

	if(obj.contains("WIN-UPGRADECODE"))
		version = installedVersion(obj.value("WIN-UPGRADECODE").toString());
	QString available = obj.value("WIN-LATEST").toString();
	request.setUrl(obj.value("WIN-DOWNLOAD").toString());
	qDebug() << "Installed version" << version << "available version" << available;

	if(!lessThanVersion(version, available))
	{
		emit status(tr("No updates are available"));
		if(m_autoclose)
			QApplication::quit();
	}
	else
	{
		if(!m_autoupdate)
		{
			if( !w ) w = new idupdaterui(version, this);
			emit status(tr("Update is available"));
		}
		else
			startInstall();
	}
	if(w) w->setInfo(version, available);
}

QString idupdater::installedVersion(const QString &upgradeCode) const
{
	QString code = upgradeCode.toUpper();
	QString path = QStringLiteral("SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall");
	HKEY reg = HKEY_LOCAL_MACHINE;
	REGSAM param = KEY_READ|KEY_WOW64_32KEY;
	HKEY key;
	long result = RegOpenKeyEx(reg, LPWSTR(path.utf16()), 0, param, &key);
	if(result != ERROR_SUCCESS)
		return {};

	DWORD numSubgroups = 0, maxSubgroupSize = 0;
	result = RegQueryInfoKey(key, 0, 0, 0, &numSubgroups, &maxSubgroupSize, 0, 0, 0, 0, 0, 0);
	if(result != ERROR_SUCCESS)
	{
		RegCloseKey(key);
		return {};
	}

	for(DWORD j = 0; j < numSubgroups; ++j)
	{
		DWORD groupSize = maxSubgroupSize + 1;
		QString group(groupSize, '\0');
		result = RegEnumKeyEx(key, j, LPWSTR(group.data()), &groupSize, 0, 0, 0, 0);
		if(result != ERROR_SUCCESS)
			return {};
		group.resize(groupSize);

		HKEY subkey;
		QString subpath = path + "\\" + group;
		result = RegOpenKeyEx(reg, LPCWSTR(subpath.utf16()), 0, param, &subkey);
		if(result != ERROR_SUCCESS)
			return {};

		DWORD numKeys = 0, maxKeySize = 0, maxValueSize = 0;
		result = RegQueryInfoKey(subkey, 0, 0, 0, 0, 0, 0, &numKeys, &maxKeySize, &maxValueSize, 0, 0);
		if(result != ERROR_SUCCESS)
		{
			RegCloseKey(subkey);
			return {};
		}

		QString regcode, version;
		for(DWORD k = 0; k < numKeys; ++k)
		{
			DWORD dataType = 0;
			DWORD keySize = maxKeySize + 1;
			DWORD dataSize = maxValueSize;
			QString key(keySize, '\0');
			QByteArray data(dataSize, 0);

			result = RegEnumValue(subkey, k, LPWSTR(key.data()), &keySize, 0,
				&dataType, (unsigned char*)data.data(), &dataSize);
			if(result != ERROR_SUCCESS)
				continue;
			key.resize(keySize);
			data.resize(dataSize);

			QString value;
			switch(dataType)
			{
			case REG_SZ:
				value = QString::fromUtf16((const ushort*)data.constData());
				break;
			case REG_MULTI_SZ:
			{
				QStringList l;
				for(int i = 0;;) {
					QString s = QString::fromUtf16((const ushort*)data.constData() + i);
					i += s.length() + 1;
					if (s.isEmpty())
						break;
					l.append(s);
				}
				value = l.value(0);
				break;
			}
			default: continue;
			}

			if(key == "BundleUpgradeCode") regcode = value;
			if(key == "DisplayVersion") version = value;
		}
		RegCloseKey(subkey);
		if(regcode.toUpper() == code)
			return version;
	}
	RegCloseKey(key);

	WCHAR prodCode[40];
	if(ERROR_SUCCESS != MsiEnumRelatedProducts(L"{58A1DBA8-81A2-4D58-980B-4A6174D5B66B}", 0, 0, prodCode))
		return {};

	DWORD size = 0;
	MsiGetProductInfo(prodCode, INSTALLPROPERTY_VERSIONSTRING, 0, &size);
	QString version(size, '\0');
	size += 1;
	MsiGetProductInfo(prodCode, INSTALLPROPERTY_VERSIONSTRING, LPWSTR(version.data()), &size);
	return version;
}

bool idupdater::lessThanVersion(const QString &current, const QString &available)
{
	QStringList curList = current.split('.');
	QStringList avaList = available.split('.');
	for(int i = 0; i < std::max<int>(curList.size(), avaList.size()); ++i)
	{
		bool curconv = false, avaconv = false;
		unsigned int cur = curList.value(i).toUInt(&curconv);
		unsigned int ava = avaList.value(i).toUInt(&avaconv);
		if(curconv && avaconv)
		{
			if(cur != ava)
				return cur < ava;
		}
		else
		{
			int status = QString::localeAwareCompare(curList.value(i), avaList.value(i));
			if(status != 0)
				return status < 0;
		}
	}
	return false;
}

void idupdater::startInstall()
{
	qDebug() << "Starting install";
	emit status( tr("Downloading...") );
	QNetworkReply *reply = get( request );
	if( w ) w->setProgress( reply );
}

bool idupdater::verifyPackage(const QString &filePath) const
{
	QString path = QDir::toNativeSeparators(filePath);
	HCERTSTORE store = nullptr;
	HCRYPTMSG msg = nullptr;
	if(!CryptQueryObject(CERT_QUERY_OBJECT_FILE, LPCWSTR(path.utf16()),
		CERT_QUERY_CONTENT_FLAG_PKCS7_SIGNED_EMBED, CERT_QUERY_FORMAT_FLAG_BINARY,
		0, 0, 0, 0, &store, &msg, nullptr))
		return false;

	DWORD infoSize = 0;
	if(!CryptMsgGetParam(msg, CMSG_SIGNER_CERT_INFO_PARAM, 0, 0, &infoSize))
	{
		CryptMsgClose(msg);
		CertCloseStore(store, 0);
		return false;
	}

	QScopedPointer<CERT_INFO,QScopedPointerPodDeleter> info(PCERT_INFO(std::malloc(infoSize)));
	if(!CryptMsgGetParam(msg, CMSG_SIGNER_CERT_INFO_PARAM, 0, info.data(), &infoSize))
	{
		CryptMsgClose(msg);
		CertCloseStore(store, 0);
		return false;
	}
	CryptMsgClose(msg);

	PCCERT_CONTEXT certContext = CertFindCertificateInStore(store,
		X509_ASN_ENCODING, 0, CERT_FIND_SUBJECT_CERT, info.data(), 0);
	CertCloseStore(store, 0);
	if(!certContext)
		return false;

	QSslCertificate cert(QByteArray::fromRawData(
		(const char*)certContext->pbCertEncoded, certContext->cbCertEncoded ), QSsl::Der);
	CertFreeCertificateContext(certContext);

	QList<QSslCertificate> list;
	for(const QJsonValue &cert: Configuration::instance().object().value("CERT-BUNDLE").toArray())
		list << QSslCertificate(QByteArray::fromBase64(cert.toString().toLatin1()), QSsl::Der);
	if(!list.contains(cert))
		return false;

	WINTRUST_FILE_INFO FileData {};
	FileData.cbStruct = sizeof(WINTRUST_FILE_INFO);
	FileData.pcwszFilePath = LPCWSTR(path.utf16());

	WINTRUST_DATA WinTrustData {};
	WinTrustData.cbStruct = sizeof(WinTrustData);
	WinTrustData.dwUIChoice = m_autoupdate ? WTD_UI_NONE : WTD_UI_ALL;
	WinTrustData.fdwRevocationChecks = WTD_REVOKE_NONE;
	WinTrustData.dwUnionChoice = WTD_CHOICE_FILE;
	WinTrustData.dwProvFlags = WTD_SAFER_FLAG;
	WinTrustData.pFile = &FileData;

	GUID WVTPolicyGUID = WINTRUST_ACTION_GENERIC_VERIFY_V2;
	return WinVerifyTrust(0, &WVTPolicyGUID, &WinTrustData) == ERROR_SUCCESS;
}
