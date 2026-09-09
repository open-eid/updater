// SPDX-FileCopyrightText: Estonian Information System Authority
// SPDX-License-Identifier: LGPL-2.1-or-later

#pragma once

#include <memory>

class ScheduledUpdateTask
{
public:
	enum Interval {
		UNKNOWN = 0,
		DAILY = 1,
		WEEKLY = 2,
		MONTHLY = 3,
		REMOVED = 4
	};
	ScheduledUpdateTask();
	~ScheduledUpdateTask();
	bool configure(Interval interval);
	int status() const;
	bool remove();

private:
	struct Private;
	std::unique_ptr<Private> d;
};
