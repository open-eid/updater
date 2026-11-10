// SPDX-FileCopyrightText: Estonian Information System Authority
// SPDX-License-Identifier: LGPL-2.1-or-later

#pragma once

#include <QApplication>

#include <QFile>

#include <memory>

class QLockFile;
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

	std::unique_ptr<QLockFile> lockFile;
	QFile log;
	QString url;
	idupdater *w = nullptr;
};

