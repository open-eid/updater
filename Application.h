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

#pragma once

#include <QApplication>

#include <QFile>
#include <QLockFile>

class idupdater;

class Application: public QApplication
{
	Q_OBJECT
public:
	explicit Application( int &argc, char **argv );
	~Application();

	int run();

private:
	static bool execute(const QStringList &arguments);
	static void msgHandler( QtMsgType type, const QMessageLogContext &ctx, const QString &msg );
	static int confTask(const QStringList &args);
	static void printHelp();

	QLockFile lockFile;
	QFile log;
	QString url;
	idupdater *w = nullptr;
};

