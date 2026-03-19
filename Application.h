// SPDX-FileCopyrightText: Estonian Information System Authority
// SPDX-License-Identifier: LGPL-2.1-or-later

#pragma once

#include <QtSingleApplication>

#include <QFile>

class idupdater;

class Application: public QtSingleApplication
{
	Q_OBJECT
public:
	explicit Application( int &argc, char **argv );
	~Application();

	int run();

private:
	bool execute(const QStringList &arguments);
	void messageReceived( const QString &str );
	static void msgHandler( QtMsgType type, const QMessageLogContext &ctx, const QString &msg );
	int confTask( const QStringList &args ) const;
	void printHelp();

	QFile log;
	QString url;
	idupdater *w = nullptr;
};

