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

#include "ProcessStarter.h"

#include <QDebug>
#include <QDir>
#include <QLibrary>

#include <windows.h>
#include <userenv.h>
#include <wtsapi32.h>

// http://www.codeproject.com/KB/vista-security/interaction-in-vista.aspx
class ProcessStarterPrivate
{
public:
	HANDLE GetCurrentUserToken();

	QString processPath;
	QStringList arguments;
};

ProcessStarter::ProcessStarter( const QString &processPath, const QStringList &arguments )
:	d( new ProcessStarterPrivate )
{
	d->processPath = QDir::toNativeSeparators( processPath );
	d->arguments = arguments;
	qDebug() << "ProcessStarter begin";
}

ProcessStarter::~ProcessStarter()
{
	qDebug() << "ProcessStarter end";
	delete d;
}

HANDLE ProcessStarterPrivate::GetCurrentUserToken()
{
	qDebug() << "GetCurrentUserToken";

	PWTS_SESSION_INFOW sessionInfo = 0;
	DWORD count = 0;
	WTSEnumerateSessionsW( WTS_CURRENT_SERVER_HANDLE, 0, 1, &sessionInfo, &count );

	DWORD sessionId = 0;
	for( DWORD i = 0; i < count; ++i)
    {
		WTS_SESSION_INFO si = sessionInfo[i];
		if( si.State == WTSActive )
        {
			sessionId = si.SessionId;
            break;
        }
    }
	WTSFreeMemory( sessionInfo );
	qDebug() << "Active session ID " << sessionId;

	HANDLE currentToken = 0;
	BOOL ret = WTSQueryUserToken( sessionId, &currentToken );
	qDebug() << "WTSQueryUserToken" << ret << GetLastError();
	if( !ret )
        return 0;

	HANDLE primaryToken = 0;
	ret = DuplicateTokenEx( currentToken, TOKEN_ASSIGN_PRIMARY | TOKEN_ALL_ACCESS, 0,
		SecurityImpersonation, TokenPrimary, &primaryToken );
	qDebug() << "DuplicateTokenEx" << ret << GetLastError();
	if( !ret )
        return 0;

    return primaryToken;
}

bool ProcessStarter::run()
{
	QString command = d->processPath + " " + d->arguments.join( " " );
	qDebug() << "command:" << command;

	HANDLE primaryToken = d->GetCurrentUserToken();
	qDebug() << "primaryToken handle" << primaryToken;
	if( !primaryToken )
		return false;

	void *environment = 0;
	BOOL result = CreateEnvironmentBlock( &environment, primaryToken, true );
	qDebug() << "CreateEnvironmentBlock" << environment << result <<  GetLastError();

	qDebug() << "creating as user";
	STARTUPINFO StartupInfo = { sizeof(StartupInfo) };
	PROCESS_INFORMATION processInfo;
	result = CreateProcessAsUserW( primaryToken, 0, LPWSTR(command.utf16()), 0, 0,
		false, CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT,
		environment, 0, &StartupInfo, &processInfo );
	CloseHandle( primaryToken );

	qDebug() << "CreateProcessAsUserW" << result << "err" << GetLastError();
	return result;
}
