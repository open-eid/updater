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

#include "Application.h"

#include "idupdater.h"
#include "ScheduledUpdateTask.h"

#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QIcon>
#include <QLocale>
#include <QMenu>
#include <QMessageBox>
#include <QSettings>
#include <QTranslator>
#include <QtNetwork/QNetworkProxyFactory>

#include <qt_windows.h>
#include <userenv.h>
#include <wtsapi32.h>

int main( int argc, char *argv[] )
{
	return Application( argc, argv ).run();
}



Application::Application( int &argc, char **argv )
:	QtSingleApplication( argc, argv )
{
	log.setFileName(QDir::tempPath() + QStringLiteral("/id-updater.log"));
	if( log.exists() && log.open( QFile::WriteOnly|QFile::Append ) )
		qInstallMessageHandler( msgHandler );

	QString lang;
	switch( QLocale().language() )
	{
	case QLocale::English: lang = QStringLiteral("en"); break;
	case QLocale::Russian: lang = QStringLiteral("ru"); break;
	case QLocale::Estonian:
	default: lang = QStringLiteral("et"); break;
	}

	QTranslator *qt = new QTranslator( this );
	QTranslator *common = new QTranslator( this );
	QTranslator *t = new QTranslator( this );
	void(qt->load(QStringLiteral(":/qtbase_%1.qm").arg(lang)));
	void(common->load(QStringLiteral(":/common_%1.qm").arg(lang)));
	void(t->load(QStringLiteral(":/idupdater_%1.qm").arg(lang)));
	installTranslator( qt );
	installTranslator( common );
	installTranslator( t );
	setLibraryPaths({ applicationDirPath() });
	setWindowIcon(QIcon(QStringLiteral(":/appicon.png")));
	setApplicationName(QStringLiteral("id-updater"));
	setApplicationVersion(QStringLiteral( "%1.%2.%3.%4" )
		.arg( MAJOR_VER ).arg( MINOR_VER ).arg( RELEASE_VER ).arg( BUILD_VER ) );
	setOrganizationDomain(QStringLiteral("ria.ee"));
	setOrganizationName(QStringLiteral("RIA"));
	QNetworkProxyFactory::setUseSystemConfiguration(true);
}

Application::~Application()
{
	qDebug() << "Application is quiting";
	qInstallMessageHandler(nullptr);
}

int Application::confTask( const QStringList &args ) const
{
	ScheduledUpdateTask task;
	if(args.contains(QStringLiteral("-status")))
		return task.status();
	if(args.contains(QStringLiteral("-daily")))
		return task.configure(ScheduledUpdateTask::DAILY);
	if(args.contains(QStringLiteral("-weekly")))
		return task.configure(ScheduledUpdateTask::WEEKLY);
	if(args.contains(QStringLiteral("-monthly")))
		return task.configure(ScheduledUpdateTask::MONTHLY);
	if(args.contains(QStringLiteral("-remove")))
		task.remove();
	return true;
}

bool Application::execute(const QStringList &arguments)
{
	// http://www.codeproject.com/KB/vista-security/interaction-in-vista.aspx
	qDebug() << "ProcessStarter begin";
	QString command = QDir::toNativeSeparators(applicationFilePath()) + " " + arguments.join(' ');
	qDebug() << "command:" << command;

	PWTS_SESSION_INFOW sessionInfo = 0;
	DWORD count = 0;
	WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE, 0, 1, &sessionInfo, &count);

	DWORD sessionId = 0;
	for(DWORD i = 0; i < count; ++i)
	{
		if(sessionInfo[i].State == WTSActive)
		{
			sessionId = sessionInfo[i].SessionId;
			break;
		}
	}
	WTSFreeMemory(sessionInfo);
	qDebug() << "Active session ID " << sessionId;

	HANDLE currentToken = 0;
	BOOL ret = WTSQueryUserToken(sessionId, &currentToken);
	qDebug() << "WTSQueryUserToken" << ret << GetLastError();
	if(!ret)
		return false;

	HANDLE primaryToken = 0;
	ret = DuplicateTokenEx(currentToken, TOKEN_ASSIGN_PRIMARY | TOKEN_ALL_ACCESS, 0,
		SecurityImpersonation, TokenPrimary, &primaryToken);
	CloseHandle(currentToken);
	qDebug() << "DuplicateTokenEx" << ret << GetLastError();
	if(!ret)
		return false;

	qDebug() << "primaryToken handle" << primaryToken;
	if(!primaryToken)
		return false;

	void *environment = nullptr;
	ret = CreateEnvironmentBlock(&environment, primaryToken, true);
	qDebug() << "CreateEnvironmentBlock" << environment << ret <<  GetLastError();

	qDebug() << "creating as user";
	STARTUPINFO StartupInfo {};
	StartupInfo.cb = sizeof(StartupInfo);
	PROCESS_INFORMATION processInfo;
	ret = CreateProcessAsUserW(primaryToken, 0, LPWSTR(command.utf16()), 0, 0,
		false, CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT,
		environment, 0, &StartupInfo, &processInfo);
	CloseHandle(primaryToken);

	qDebug() << "CreateProcessAsUserW" << ret << "err" << GetLastError();
	qDebug() << "ProcessStarter end";
	return ret;
}

void Application::messageReceived( const QString &str )
{
	w->checkUpdates(str.contains("-autoupdate"), str.contains("-autoclose"));
}

void Application::msgHandler( QtMsgType type, const QMessageLogContext &, const QString &msg )
{
	QFile *log = &qobject_cast<Application*>(qApp->instance())->log;
	log->write(QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd hh:mm:ss:zzz ")).toUtf8());
	switch( type )
	{
	case QtDebugMsg: log->write(QStringLiteral("DBG: %1\n").arg(msg).toUtf8()); break;
	case QtInfoMsg: log->write(QStringLiteral("INF: %1\n").arg(msg).toUtf8()); break;
	case QtWarningMsg: log->write(QStringLiteral("WRN: %1\n").arg(msg).toUtf8()); break;
	case QtCriticalMsg: log->write(QStringLiteral("CRI: %1\n").arg( msg).toUtf8()); break;
	case QtFatalMsg: log->write(QStringLiteral("FAT: %1\n").arg(msg).toUtf8()); abort();
	}
}

void Application::printHelp()
{
	QMessageBox::information(nullptr, QStringLiteral("ID Updater"), QStringLiteral(
		"<table><tr><td>-help</td><td>%1</td></tr>"
		"<tr><td>-autoupdate</td><td>%2</td></tr>"
		"<tr><td>-autoclose</td><td>%3</td></tr>"
		"<tr><td>-task</td><td>%4</td></tr>"
		"<tr><td colspan=\"2\">-daily|-monthly|-weekly|-remove</td></tr>"
		"<tr><td colspan=\"2\">%6</td></tr></table>").arg(
		tr("this help"),
		tr("update automatically"),
		tr("close automatically when no updates are available"),
		tr("execute subprocess to right window session under windows"),
		tr("configure scheduled task to run at given interval, or remove it")));
}

int Application::run()
{
	QStringList args = arguments();
	args.removeFirst();
	qDebug() << "Starting updater with arguments" << args;
	if( args.contains("-help") || args.contains("-?") || args.contains("/?") )
	{
		printHelp();
		return 0;
	}
	if( args.contains("-daily") || args.contains("-weekly") || args.contains("-monthly") || args.contains("-remove") )
	{
		int result = confTask( args );
		if( !result )
			QMessageBox::warning( 0, "ID Updater",
				tr("Failed to set schedule, check permissions. Try again with administrator permissions.") );
		return !result;
	}

	if(args.contains("-status"))
		return confTask( args );

	if( args.contains("-task") )
	{
		args.removeAll( "-task" );
		args << "-autoclose";
		return !execute(args);
	}

	if( isRunning() )
		return !sendMessage( args.join( " " ) );
	connect( this, &QtSingleApplication::messageReceived, this, &Application::messageReceived );

	w = new idupdater( this );
	w->checkUpdates(args.contains("-autoupdate"), args.contains("-autoclose"));

	return exec();
}
