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

using namespace Qt::StringLiterals;

int main( int argc, char *argv[] )
{
	return Application( argc, argv ).run();
}



Application::Application( int &argc, char **argv )
:	QtSingleApplication( argc, argv )
{
	log.setFileName(QDir::tempPath() + u"/id-updater.log"_s);
	if( log.exists() && log.open( QFile::WriteOnly|QFile::Append ) )
		qInstallMessageHandler( msgHandler );

	QTranslator *qt = new QTranslator( this );
	QTranslator *common = new QTranslator( this );
	QTranslator *t = new QTranslator( this );
	QString lang;
	auto languages = QLocale().uiLanguages().first();
	if(languages.contains("et"_L1, Qt::CaseInsensitive))
		lang = u"et"_s;
	else if(languages.contains("ru"_L1, Qt::CaseInsensitive))
		lang = u"ru"_s;
	else
		lang = u"en"_s;
	void(qt->load(":/qtbase_%1.qm"_L1.arg(lang)));
	void(common->load(":/common_%1.qm"_L1.arg(lang)));
	void(t->load(":/idupdater_%1.qm"_L1.arg(lang)));
	installTranslator( qt );
	installTranslator( common );
	installTranslator( t );
#ifdef NDEBUG
	setLibraryPaths({ applicationDirPath() });
#endif
	setWindowIcon(QIcon(u":/appicon.png"_s));
	setApplicationName(u"id-updater"_s);
	setApplicationVersion(u"%1.%2.%3.%4"_s
		.arg( MAJOR_VER ).arg( MINOR_VER ).arg( RELEASE_VER ).arg( BUILD_VER ) );
	setOrganizationDomain(u"ria.ee"_s);
	setOrganizationName(u"RIA"_s);
	setStyle(u"windowsvista"_s);
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
	if(args.contains("-status"_L1))
		return task.status();
	if(args.contains("-daily"_L1))
		return task.configure(ScheduledUpdateTask::DAILY);
	if(args.contains("-weekly"_L1))
		return task.configure(ScheduledUpdateTask::WEEKLY);
	if(args.contains("-monthly"_L1))
		return task.configure(ScheduledUpdateTask::MONTHLY);
	if(args.contains("-remove"_L1))
		task.remove();
	return true;
}

bool Application::execute(const QStringList &arguments)
{
	// http://www.codeproject.com/KB/vista-security/interaction-in-vista.aspx
	qDebug() << "ProcessStarter begin";
	QString command = QDir::toNativeSeparators(applicationFilePath()) + ' ' + arguments.join(' ');
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
	STARTUPINFO StartupInfo { sizeof(StartupInfo) };
	PROCESS_INFORMATION processInfo {};
	ret = CreateProcessAsUserW(primaryToken, nullptr, LPWSTR(command.utf16()),
		 nullptr, nullptr, false, CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT,
		environment, nullptr, &StartupInfo, &processInfo);
	CloseHandle(primaryToken);

	qDebug() << "CreateProcessAsUserW" << ret << "err" << GetLastError();
	qDebug() << "ProcessStarter end";
	return ret;
}

void Application::messageReceived( const QString &str )
{
	w->checkUpdates(str.contains("-autoupdate"_L1), str.contains("-autoclose"_L1));
}

void Application::msgHandler( QtMsgType type, const QMessageLogContext &, const QString &msg )
{
	QFile *log = &qobject_cast<Application*>(qApp)->log;
	log->write(QDateTime::currentDateTime().toString(u"yyyy-MM-dd hh:mm:ss:zzz "_s).toUtf8());
	switch( type )
	{
	case QtDebugMsg: log->write("DBG: %1\n"_L1.arg(msg).toUtf8()); break;
	case QtInfoMsg: log->write("INF: %1\n"_L1.arg(msg).toUtf8()); break;
	case QtWarningMsg: log->write("WRN: %1\n"_L1.arg(msg).toUtf8()); break;
	case QtCriticalMsg: log->write("CRI: %1\n"_L1.arg( msg).toUtf8()); break;
	case QtFatalMsg: log->write("FAT: %1\n"_L1.arg(msg).toUtf8()); abort();
	}
}

void Application::printHelp()
{
	QMessageBox::information(nullptr, u"ID Updater"_s,
		"<table><tr><td>-help</td><td>%1</td></tr>"
		"<tr><td>-autoupdate</td><td>%2</td></tr>"
		"<tr><td>-autoclose</td><td>%3</td></tr>"
		"<tr><td>-task</td><td>%4</td></tr>"
		"<tr><td colspan=\"2\">-daily|-monthly|-weekly|-remove</td></tr>"
		"<tr><td colspan=\"2\">%6</td></tr></table>"_L1.arg(
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
	if(args.contains("-help"_L1) || args.contains("-?"_L1) || args.contains("/?"_L1))
	{
		printHelp();
		return 0;
	}
	if(args.contains("-daily"_L1) || args.contains("-weekly"_L1) || args.contains("-monthly"_L1) || args.contains("-remove"_L1))
	{
		int result = confTask( args );
		if( !result )
			QMessageBox::warning(nullptr, u"ID Updater"_s,
				tr("Failed to set schedule, check permissions. Try again with administrator permissions.") );
		return !result;
	}

	if(args.contains("-status"_L1))
		return confTask( args );

	if( args.contains("-task"_L1) )
	{
		args.removeAll("-task"_L1);
		args.append(u"-autoclose"_s);
		return !execute(args);
	}

	if( isRunning() )
		return !sendMessage(args.join(' '));
	connect( this, &QtSingleApplication::messageReceived, this, &Application::messageReceived );

	w = new idupdater( this );
	w->checkUpdates(args.contains("-autoupdate"_L1), args.contains("-autoclose"_L1));

	return exec();
}
