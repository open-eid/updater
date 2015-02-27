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

#include "InstallChecker.h"
#include "common/QPCSC.h"

#include <QDebug>
#include <QDir>
#include <QElapsedTimer>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLibrary>
#include <QNetworkReply>
#include <QPushButton>
#include <QUrl>
#include <QXmlStreamReader>

#include <qt_windows.h>

static bool lessThanVersion( const QString &current, const QString &available )
{
	QStringList curList = current.split('.');
	QStringList avaList = available.split('.');
	for( int i = 0; i < std::max<int>(curList.size(), avaList.size()); ++i )
	{
		bool curconv = false, avaconv = false;
		unsigned int cur = curList.value(i).toUInt( &curconv );
		unsigned int ava = avaList.value(i).toUInt( &avaconv );
		if( curconv && avaconv )
		{
			if( cur != ava )
				return cur < ava;
		}
		else
		{
			int status = QString::localeAwareCompare( curList.value(i), avaList.value(i) );
			if( status != 0 )
				return status < 0;
		}
	}
	return false;
}

idupdaterui::idupdaterui( idupdater *parent )
:	QWidget()
{
	setupUi( this );
	connect( parent, &idupdater::status, m_updateStatus, &QLabel::setText );
	connect( parent, &idupdater::error, this, &idupdaterui::setError );
	connect( buttonBox, &QDialogButtonBox::accepted, parent, &idupdater::startInstall );
	connect( buttonBox,  &QDialogButtonBox::rejected, qApp, &QCoreApplication::quit );
	buttonBox->button( QDialogButtonBox::Ok )->setText( tr("Start downloading") );
	buttonBox->button( QDialogButtonBox::Close )->setText( tr("Close") );
	setDownloadEnabled( false );
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
	setDownloadEnabled( lessThanVersion( version, available ) );
	m_installedVer->setText( version );
	m_availableVer->setText( available );
}

void idupdaterui::setProgress( QNetworkReply *reply )
{
	buttonBox->button( QDialogButtonBox::Ok )->setEnabled( false );
	m_downloadProgress->setValue( 0 );
	connect( reply, &QNetworkReply::downloadProgress, [&]( qint64 recvd, qint64 total ) {
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
:	QNetworkAccessManager( parent )
,	m_autoupdate( false )
,	m_autoclose( false )
,	w(0)
{
	QLocale::Language language = QLocale::system().language();
	QString locale = language == QLocale::C ? "English/United States" : QLocale::languageToString( language );
	CPINFOEX CPInfoEx = { 0 };
	if( GetCPInfoExW( GetConsoleCP(), 0, &CPInfoEx ) != 0 )
		locale += " / " + QString( (QChar*)CPInfoEx.CodePageName );
	QPCSC pcsc;
	QString userAgent = QString( "%1/%2 (%3) Locale: %4 Devices: %5")
		.arg( qApp->applicationName(), InstallChecker::installedVersion("{58A1DBA8-81A2-4D58-980B-4A6174D5B66B}"), applicationOs(), locale, pcsc.drivers().join("/") );
	qDebug() << "User-Agent:" << userAgent;
	request.setRawHeader( "User-Agent", userAgent.toUtf8() );
	connect( this, &QNetworkAccessManager::finished, this, &idupdater::reply );
	chromeCheck();
}

QString idupdater::applicationOs()
{
	OSVERSIONINFOEX osvi = { sizeof( OSVERSIONINFOEX ) };
	if( GetVersionEx( (OSVERSIONINFO *)&osvi ) )
	{
		bool workstation = osvi.wProductType == VER_NT_WORKSTATION;
		SYSTEM_INFO si;
		typedef void (WINAPI *PGNSI)(LPSYSTEM_INFO);
		if( PGNSI pGNSI = PGNSI( QLibrary( "kernel32" ).resolve( "GetNativeSystemInfo" ) ) )
			pGNSI( &si );
		else
			GetSystemInfo( &si );
		QString os;
		switch( (osvi.dwMajorVersion << 8) + osvi.dwMinorVersion )
		{
		case 0x0500: os = workstation ? "2000 Professional" : "2000 Server"; break;
		case 0x0501: os = osvi.wSuiteMask & VER_SUITE_PERSONAL ? "XP Home" : "XP Professional"; break;
		case 0x0502:
			if( GetSystemMetrics( SM_SERVERR2 ) )
				os = "Server 2003 R2";
			else if( workstation && si.wProcessorArchitecture == PROCESSOR_ARCHITECTURE_AMD64 )
				os = "XP Professional";
			else
				os = "Server 2003";
			break;
		case 0x0600: os = workstation ? "Vista" : "Server 2008"; break;
		case 0x0601: os = workstation ? "7" : "Server 2008 R2"; break;
		case 0x0602: os = workstation ? "8" : "Server 2012"; break;
		case 0x0603: os = workstation ? "8.1" : "Server 2012 R2"; break;
		case 0x0A00: os = workstation ? "10" : "Server 10"; break;
		default: break;
		}
		return QString( "Windows %1 %2(%3 bit)" ).arg( os )
			.arg( osvi.szCSDVersion ? QString( (const QChar*)osvi.szCSDVersion ) + " " : "" )
			.arg( si.wProcessorArchitecture == PROCESSOR_ARCHITECTURE_AMD64 ? "64" : "32" );
	}
	else
	{
		switch( QSysInfo::WindowsVersion )
		{
		case QSysInfo::WV_2000: return "Windows 2000"; break;
		case QSysInfo::WV_XP: return "Windows XP"; break;
		case QSysInfo::WV_2003: return "Windows 2003"; break;
		case QSysInfo::WV_VISTA: return "Windows Vista"; break;
		case QSysInfo::WV_WINDOWS7: return "Windows 7"; break;
		case QSysInfo::WV_WINDOWS8: return "Windows 8"; break;
		default: break;
		}
	}
	return tr("Unknown OS");
}

void idupdater::chromeCheck()
{
	for( const QString &user: QDir("/Users").entryList() )
	{
		static QStringList ignore( { ".", "..", "Public", "All Users", "Default", "Default User" } );
		if( ignore.contains(user) )
			continue;

		QFile conf( "/Users/" + user + "/AppData/Local/Google/Chrome/User Data/Local State");
		qDebug() << "User" << conf.fileName();
		if( !conf.open(QFile::ReadWrite) )
			continue;

		QJsonDocument doc = QJsonDocument::fromJson(conf.readAll());
		QJsonObject obj = doc.object();
		QString ver = obj.value("user_experience_metrics").toObject().value("stability").toObject().value("stats_version").toString();
		qDebug() << "Chrome version" << ver;
		if( lessThanVersion( ver, "42.0.0.0" ) )
			continue;

		QJsonObject browser = obj.value("browser").toObject();
		QJsonArray list = browser.value("enabled_labs_experiments").toArray();
		qDebug() << "enable-npapi" << list.contains("enable-npapi");
		if( list.contains("enable-npapi") )
			continue;

		list << "enable-npapi";
		browser["enabled_labs_experiments"] = list;
		obj["browser"] = browser;
		doc.setObject(obj);
		conf.seek(0);
		conf.write( doc.toJson() );
	}
}

void idupdater::reply( QNetworkReply *reply )
{
	switch( reply->error() )
	{
	case QNetworkReply::NoError: break;
	default: emit error( reply->errorString() ); reply->deleteLater(); return;
	}

	if( reply->property( "filename" ).isNull() )
	{
		emit status( tr("Check completed") );
		QXmlStreamReader xml( reply );

		xml.readNextStartElement();
		if( xml.name() == "message" )
			return emit status( xml.readElementText() );
		if( xml.name() != "products" )
			return emit error( tr("could not load a valid update file") );

		if( !xml.readNextStartElement() || xml.name() != "product" )
			return emit error( tr("could not load a valid update file") );

		QXmlStreamAttributes attr = xml.attributes();
		filename = attr.value( "filename" ).toString();
		QString version = InstallChecker::installedVersion( attr.value( "UpgradeCode" ).toString() );
		QString available = attr.value( "ProductVersion" ).toString();
		QString product = attr.value( "ProductName" ).toString();
		reply->deleteLater();

		qDebug() << "Installed version" << version << "available version" << available;

		if( !lessThanVersion( version, available ) )
		{
			emit status( tr("No updates are available") );
			if( m_autoclose )
				QApplication::quit();
		}
		else
		{
			if( !m_autoupdate )
			{
				if( !w ) w = new idupdaterui( this );
				emit status( tr("Update is available") + "\n" + product );
			}
			else
				startInstall();
		}
		if( w ) w->setInfo( version, available );
	}
	else
	{
		qDebug() << "Downloaded" << reply->property( "filename" ).toString() << "from" << reply->url().toString();
		emit status( tr("Download finished, starting installation...") );
		QFile tmp( QDir::tempPath() + "/" + reply->property( "filename" ).toString() );
		if( !tmp.open( QFile::WriteOnly ) )
			return emit error( tr("Downloaded package integrity check failed") );

		tmp.write( reply->readAll() );
		tmp.close();
		reply->deleteLater();

		bool verify = InstallChecker::verifyPackage( tmp.fileName(), !m_autoupdate );
		qDebug() << "Package signature" << (verify ? "OK" : "NOT OK");
		if( !verify )
			return emit error( tr("Downloaded package integrity check failed") );
		if( !InstallChecker::installPackage( tmp.fileName(), m_autoupdate ) )
			return emit error( tr("Package installation failed") );
		emit status( tr("Package installed") );
		QApplication::quit();
	}
}

void idupdater::checkUpdates( const QString &url, bool autoupdate, bool autoclose )
{
	m_autoupdate = autoupdate;
	m_autoclose = autoclose;
	if( !autoclose && !w )
	{
		w = new idupdaterui( this );
		request.setRawHeader( "User-Agent", request.rawHeader( "User-Agent" ) + " manual" );
	}
	m_baseUrl = url;
	emit status( tr("Checking for update..") );
	request.setUrl( m_baseUrl + "/products.xml" );
	qDebug() << "Url:" << request.url().toString();
	if( request.url().scheme() != "http" ||
		request.url().scheme() != "ftp" ||
		request.url().scheme() != "https" )
		get( request );
	else
		emit error( tr("Unsupported protocol in url") );
}

void idupdater::startInstall()
{
	qDebug() << "Starting install";
	emit status( tr("Downloading...") );
	request.setUrl( m_baseUrl + "/" + filename );
	QNetworkReply *reply = get( request );
	reply->setProperty( "filename", filename );
	if( w ) w->setProgress( reply );
}
