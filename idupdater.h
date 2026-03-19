// SPDX-FileCopyrightText: Estonian Information System Authority
// SPDX-License-Identifier: LGPL-2.1-or-later

#pragma once

#include "ui_idupdater.h"

#include <QNetworkAccessManager>

#include <QNetworkRequest>

class Configuration;
class idupdater;
class idupdaterui: public QWidget, private Ui::idupdaterui
{
	Q_OBJECT
public:
	explicit idupdaterui(const QString &version, idupdater *parent = 0);

	void setDownloadEnabled( bool enabled );
	void setInfo( const QString &version, const QString &available );
	void setProgress( QNetworkReply *reply );
};


class idupdater : public QNetworkAccessManager
{
	Q_OBJECT

public:
	explicit idupdater( QObject *parent = 0 );

	void checkUpdates(bool autoupdate, bool autoclose);
	void startInstall();

	static bool lessThanVersion( const QString &current, const QString &available );

Q_SIGNALS:
	void error( const QString &msg );
	void status( const QString &msg );
	void message(const QString &msg);

private:
	void finished(bool changed, const QString &error);
	QString installedVersion(const QString &upgradeCode) const;
	bool verifyPackage(const QString &filePath) const;

	bool m_autoupdate = false, m_autoclose = false;
	QNetworkRequest request;
	QString version;
	Configuration *conf {};
	idupdaterui *w {};
	QList<QSslCertificate> trusted;
};
