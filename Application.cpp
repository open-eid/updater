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
#include "ProcessStarter.h"

#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QIcon>
#include <QLocale>
#include <QMenu>
#include <QMessageBox>
#include <QSettings>
#include <QTextCodec>
#include <QTranslator>
#include <QtNetwork/QNetworkProxyFactory>

#ifndef TASK_NAME
#define TASK_NAME "id updater task"
#endif
#ifndef UPDATER_URL
#define UPDATER_URL "http://ftp.id.eesti.ee/pub/id/updater/"
#endif

Application::Application( int &argc, char **argv )
:	QtSingleApplication( argc, argv )
,	url( UPDATER_URL )
,	w(0)
{
	log.setFileName( QDir::tempPath() + "/id-updater.log" );
	if( log.exists() && log.open( QFile::WriteOnly|QFile::Append ) )
		qInstallMessageHandler( msgHandler );

	QString lang;
	switch( QLocale().language() )
	{
	case QLocale::English: lang = "en"; break;
	case QLocale::Russian: lang = "ru"; break;
	case QLocale::Estonian:
	default: lang = "et"; break;
	}
	lang = QSettings( "Estonian ID Card", QString() ).value( "Main/Language", lang ).toString();

	QTranslator *qt = new QTranslator( this );
	QTranslator *t = new QTranslator( this );
	qt->load( QString(":/qtbase_%1.qm").arg( lang ) );
	t->load( QString(":/idupdater_%1.qm").arg( lang ) );
	installTranslator( qt );
	installTranslator( t );
	setLibraryPaths( QStringList() << applicationDirPath() );
	setWindowIcon( QIcon( ":/appicon.png" ) );
	setApplicationName( APP );
	setApplicationVersion( QString( "%1.%2.%3.%4" )
		.arg( MAJOR_VER ).arg( MINOR_VER ).arg( RELEASE_VER ).arg( BUILD_VER ) );
	setOrganizationDomain( DOMAINURL );
	setOrganizationName( ORG );
	QNetworkProxyFactory::setUseSystemConfiguration(true);
}

Application::~Application()
{
	qDebug() << "Application is quiting";
	qInstallMessageHandler( 0 );
}

QStringList Application::cleanParams( const QStringList &args ) const
{
	QStringList ret = args;
	ret.removeAll("-daily");
	ret.removeAll("-weekly");
	ret.removeAll("-monthly");
	ret.removeAll("-never");
	ret.removeAll("-remove");
	ret.removeAll("-task");
	ret.removeAll("-autoclose");
	ret.removeAll("-status");
	ret.removeAll("-chrome-npapi");
	return ret;
}

int Application::confTask( const QStringList &args ) const
{
	ScheduledUpdateTask task( "id-updater.exe", TASK_NAME );
	if( args.contains("-status") )
		return task.status();
	if( args.contains("-daily") )
		return task.configure( ScheduledUpdateTask::DAILY, cleanParams( args ) );
	if( args.contains("-weekly") )
		return task.configure( ScheduledUpdateTask::WEEKLY, cleanParams( args ) );
	if( args.contains("-monthly") )
		return task.configure( ScheduledUpdateTask::MONTHLY, cleanParams( args ) );
	if( args.contains("-remove") )
		task.remove();
	return true;
}

void Application::messageReceived( const QString &str )
{
	int pos = str.indexOf( "-url" );
	if( pos != -1 )
		url = str.mid( pos + 5 );
	w->checkUpdates( url, str.contains( "-autoupdate" ), str.contains( "-autoclose" ) );
}

void Application::msgHandler( QtMsgType type, const QMessageLogContext &, const QString &msg )
{
	QFile *log = &qobject_cast<Application*>(qApp->instance())->log;
	log->write( QDateTime::currentDateTime().toString( "yyyy-MM-dd hh:mm:ss:zzz " ).toUtf8() );
	switch( type )
	{
	case QtDebugMsg: log->write( QString( "DBG: %1\n" ).arg( msg ).toUtf8() ); break;
	case QtWarningMsg: log->write( QString( "WRN: %1\n" ).arg( msg ).toUtf8() ); break;
	case QtCriticalMsg: log->write( QString( "CRI: %1\n" ).arg( msg ).toUtf8() ); break;
	case QtFatalMsg: log->write( QString( "FAT: %1\n" ).arg( msg ).toUtf8() ); abort();
	}
}

void Application::printHelp()
{
	QMessageBox::information( 0, "ID Updater", QString(
		"<table><tr><td>-help</td><td>%1</td></tr>"
		"<tr><td>-autoupdate</td><td>%2</td></tr>"
		"<tr><td>-autoclose</td><td>%3</td></tr>"
		"<tr><td>-task</td><td>%4</td></tr>"
		"<tr><td>-url http://foo.bar</td><td>%5</td></tr>"
		"<tr><td colspan=\"2\">-daily|-monthly|-weekly|-remove</td></tr>"
		"<tr><td colspan=\"2\">%6</td></tr></table>")
		.arg( tr("this help") )
		.arg( tr("update automatically") )
		.arg( tr("close automatically when no updates are available") )
		.arg( tr("execute subprocess to right window session under windows") )
		.arg( tr("use alternate url") )
		.arg( tr("configure scheduled task to run at given interval, or remove it") ) );
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

	if( args.contains("-status") || args.contains("-chrome-npapi") )
		return confTask( args );

	if( args.contains("-task") )
	{
		args.removeAll( "-task" );
		args << "-autoclose";
		return !ProcessStarter( applicationFilePath(), args ).run();
	}

	int urlAt = args.indexOf("-url");
	if( urlAt != -1 )
		url = args.value( urlAt + 1, UPDATER_URL );

	if( isRunning() )
		return !sendMessage( args.join( " " ) );
	connect( this, &QtSingleApplication::messageReceived, this, &Application::messageReceived );

	w = new idupdater( this );
	w->checkUpdates( url, args.contains( "-autoupdate" ), args.contains( "-autoclose" ) );

	return exec();
}
