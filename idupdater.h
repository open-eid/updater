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
	explicit idupdaterui( idupdater *parent = 0 );

	void setDownloadEnabled( bool enabled );
	void setInfo( const QString &version, const QString &available );
	void setProgress( QNetworkReply *reply );

private:
	void setError( const QString &msg );
};


class idupdater : public QNetworkAccessManager
{
	Q_OBJECT

public:
	explicit idupdater( QObject *parent = 0 );

	void checkUpdates( const QString &url, bool autoupdate, bool autoclose );
	void startInstall();

signals:
	void error( const QString &msg );
	void status( const QString &msg );

private:
	QString applicationOs();
	void reply( QNetworkReply *reply );

	bool m_autoupdate, m_autoclose;
	QString m_baseUrl, filename;
	QNetworkRequest request;
	idupdaterui *w;
};
