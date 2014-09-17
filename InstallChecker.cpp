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

#include "InstallChecker.h"

#include <QDir>
#include <QProcess>
#include <QScopedPointer>

#include <Windows.h>
#include <Msi.h>
#include <Softpub.h>

class BinaryCertificate
{
public:
	BinaryCertificate( LPCWSTR path )
	: store( 0 )
	, msg( 0 )
	, certContext( 0 )
	{
		if( !CryptQueryObject( CERT_QUERY_OBJECT_FILE, path,
			CERT_QUERY_CONTENT_FLAG_PKCS7_SIGNED_EMBED, CERT_QUERY_FORMAT_FLAG_BINARY,
			0, 0, 0, 0, &store, &msg, NULL ) )
			return;

		DWORD infoSize = 0;
		if( !CryptMsgGetParam( msg, CMSG_SIGNER_CERT_INFO_PARAM, 0, 0, &infoSize ) )
			return;
		QScopedPointer<CERT_INFO,QScopedPointerPodDeleter> info( (PCERT_INFO)std::malloc( infoSize ) );
		if( !CryptMsgGetParam( msg, CMSG_SIGNER_CERT_INFO_PARAM, 0, info.data(), &infoSize ) )
			return;

		certContext = CertFindCertificateInStore( store,
			X509_ASN_ENCODING, 0, CERT_FIND_SUBJECT_CERT, info.data(), 0 );
	}

	~BinaryCertificate()
	{
		if( certContext ) CertFreeCertificateContext( certContext );
		if( store ) CertCloseStore( store, 0 );
		if( msg ) CryptMsgClose( msg );
	}

	QString subjectName() const
	{
		if( !certContext )
			return QString();
		DWORD size = CertGetNameString( certContext, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0, 0, 0, 0 );
		QString name( size - 1, 0 );
		CertGetNameString( certContext, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0, 0, LPWSTR(name.data()), size );
		return name;
	}

private:
	PCCERT_CONTEXT certContext;
	HCERTSTORE store;
	HCRYPTMSG msg;
};

QString InstallChecker::installedVersion( const QString &upgradeCode )
{
	WCHAR prodCode[40];
	if( ERROR_SUCCESS != MsiEnumRelatedProducts( LPCWSTR(upgradeCode.utf16()), 0, 0, prodCode ) )
		return "none";

	DWORD size = 0;
	MsiGetProductInfo( prodCode, INSTALLPROPERTY_VERSIONSTRING, 0, &size );
	QString version( size, 0 );
	size += 1;
	MsiGetProductInfo( prodCode, INSTALLPROPERTY_VERSIONSTRING, LPWSTR(version.data()), &size );
	return version;
}

bool InstallChecker::installPackage( const QString &filePath, bool reducedUI )
{
	QStringList params = QStringList()
		<< "REINSTALLMODE=vdmus"
		<< "ALLUSERS=1"
		<< "/I" << QDir::toNativeSeparators( filePath )
		<< "/l*" << QDir::toNativeSeparators( QDir::tempPath() + "/esteid_inst.log" );
	if( reducedUI )
		params << "/qn+";
	return QProcess::startDetached( "msiexec.exe", params );
}

bool InstallChecker::verifyPackage( const QString &filePath, bool withUI )
{
	QString path = QDir::toNativeSeparators( filePath );

	BinaryCertificate c( LPCWSTR(path.utf16()) );
	if( c.subjectName() != "Estonian Informatics Centre" &&
		c.subjectName() != "RIIGI INFOSUSTEEMI AMET" )
		return false;

	WINTRUST_FILE_INFO FileData = { sizeof(WINTRUST_FILE_INFO) };
	FileData.pcwszFilePath = LPCWSTR(path.utf16());

	WINTRUST_DATA WinTrustData = { sizeof(WinTrustData) };
	WinTrustData.dwUIChoice = withUI ? WTD_UI_ALL : WTD_UI_NONE;
	WinTrustData.fdwRevocationChecks = WTD_REVOKE_NONE; 
	WinTrustData.dwUnionChoice = WTD_CHOICE_FILE;
	WinTrustData.dwProvFlags = WTD_SAFER_FLAG;
	WinTrustData.pFile = &FileData;

	GUID WVTPolicyGUID = WINTRUST_ACTION_GENERIC_VERIFY_V2;
	switch( WinVerifyTrust( 0, &WVTPolicyGUID, &WinTrustData ) )
	{
	case ERROR_SUCCESS: return true;
	default: return false;
	}
}
