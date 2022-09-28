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

#include "ui_idupdater.h"

#include <QNetworkAccessManager>

#include <QNetworkRequest>

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
	idupdaterui *w = nullptr;
    QList<QSslCertificate> trusted;
};
