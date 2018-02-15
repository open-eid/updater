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

#include "ScheduledUpdateTask.h"

#include <QCoreApplication>
#include <QDir>
#include <QTime>

#include <comutil.h>
#include <Mstask.h>
#include <Taskschd.h>

#ifndef TASK_NAME
#define TASK_NAME L"id updater task"
#endif

template <class T>
class CPtr
{
	T *d;
 public:
	CPtr(T *p = nullptr): d(p) {}
	~CPtr() { if(d) d->Release(); }
	inline T* operator->() const { return d; }
	inline operator T*() const { return d; }
	inline T** operator&() { return &d; }
};

class ScheduledUpdateTaskPrivate
{
public:
	CPtr<ITaskService> service;
	CPtr<ITaskFolder> folder;
};



ScheduledUpdateTask::ScheduledUpdateTask()
	: d(new ScheduledUpdateTaskPrivate)
{
	CoInitialize( 0 );
	CoInitializeSecurity( 0, -1, 0, 0, RPC_C_AUTHN_LEVEL_PKT_PRIVACY,
		RPC_C_IMP_LEVEL_IMPERSONATE, 0, 0, 0 );
	CoCreateInstance( CLSID_TaskScheduler, 0, CLSCTX_INPROC_SERVER,
		IID_PPV_ARGS(&d->service) );
	d->service->Connect( _variant_t(), _variant_t(), _variant_t(), _variant_t() );
	d->service->GetFolder( _bstr_t(L"\\"), &d->folder );
}

ScheduledUpdateTask::~ScheduledUpdateTask()
{
	delete d;
	CoUninitialize();
}

bool ScheduledUpdateTask::configure(ScheduledUpdateTask::Interval interval)
{
	if( !d->service )
		return false;

	CPtr<ITaskDefinition> task;
	if( FAILED(d->service->NewTask( 0, &task )) )
		return false;

	CPtr<ITaskSettings> settings;
	if( SUCCEEDED(task->get_Settings( &settings )) )
	{
		settings->put_StartWhenAvailable( VARIANT_BOOL(true) );
		settings->put_RunOnlyIfNetworkAvailable( VARIANT_BOOL(true) );
		settings->put_DisallowStartIfOnBatteries( VARIANT_BOOL(false) );
		settings->put_StopIfGoingOnBatteries( VARIANT_BOOL(false) );
	}

	CPtr<ITriggerCollection> triggerCollection;
	if( FAILED(task->get_Triggers( &triggerCollection )) )
		return false;

	QDateTime t = QDateTime::currentDateTime();
	switch( interval )
	{
	case ScheduledUpdateTask::DAILY:
	{
		CPtr<ITrigger> trigger;
		CPtr<IDailyTrigger> dailyTrigger;
		if( FAILED(triggerCollection->Create( TASK_TRIGGER_DAILY, &trigger )) ||
			FAILED(trigger->QueryInterface( IID_PPV_ARGS(&dailyTrigger) )) ||
			FAILED(dailyTrigger->put_StartBoundary( _bstr_t(t.toString("yyyy-MM-ddTHH:mm:ss").utf16()) )) )
			return false;
		break;
	}
	case ScheduledUpdateTask::WEEKLY:
	{
		short day = 0;
		switch( t.date().dayOfWeek() )
		{
		case Qt::Monday: day = TASK_MONDAY; break;
		case Qt::Tuesday: day = TASK_TUESDAY; break;
		case Qt::Wednesday: day = TASK_WEDNESDAY; break;
		case Qt::Thursday: day = TASK_THURSDAY; break;
		case Qt::Friday: day = TASK_FRIDAY; break;
		case Qt::Saturday: day = TASK_SATURDAY; break;
		case Qt::Sunday: day = TASK_SUNDAY; break;
		default: day = TASK_MONDAY; break;
		}
		CPtr<ITrigger> trigger;
		CPtr<IWeeklyTrigger> weeklyTrigger;
		if( FAILED(triggerCollection->Create( TASK_TRIGGER_WEEKLY, &trigger )) ||
			FAILED(trigger->QueryInterface( IID_PPV_ARGS(&weeklyTrigger) )) ||
			FAILED(weeklyTrigger->put_StartBoundary( _bstr_t(t.toString("yyyy-MM-ddTHH:mm:ss").utf16()) )) ||
			FAILED(weeklyTrigger->put_DaysOfWeek( day )) )
			return false;
		break;
	}
	case ScheduledUpdateTask::MONTHLY:
	{
		CPtr<ITrigger> trigger;
		CPtr<IMonthlyTrigger> monthlyTrigger;
		if( FAILED(triggerCollection->Create( TASK_TRIGGER_MONTHLY, &trigger )) ||
			FAILED(trigger->QueryInterface( IID_PPV_ARGS(&monthlyTrigger) )) ||
			FAILED(monthlyTrigger->put_StartBoundary( _bstr_t(t.toString("yyyy-MM-ddTHH:mm:ss").utf16()) )) ||
			FAILED(monthlyTrigger->put_DaysOfMonth(1 << (t.date().day() - 1))))
			return false;
		break;
	}
	}

	QString command = QDir::toNativeSeparators(qApp->applicationFilePath());
	CPtr<IActionCollection> actionCollection;
	CPtr<IAction> action;
	CPtr<IExecAction> execAction;
	CPtr<IRegisteredTask> registeredTask;
	return SUCCEEDED(task->get_Actions( &actionCollection )) &&
		SUCCEEDED(actionCollection->Create( TASK_ACTION_EXEC, &action )) &&
		SUCCEEDED(action->QueryInterface( IID_PPV_ARGS(&execAction) )) &&
		SUCCEEDED(execAction->put_Path( _bstr_t(command.utf16()) )) &&
		SUCCEEDED(execAction->put_Arguments( _bstr_t(L"-task") )) &&
		SUCCEEDED(d->folder->RegisterTaskDefinition(
			_bstr_t(TASK_NAME), task, TASK_CREATE_OR_UPDATE,
			_variant_t(L"SYSTEM"), _variant_t(),
			TASK_LOGON_SERVICE_ACCOUNT, _variant_t(L""), &registeredTask ));
}

int ScheduledUpdateTask::status() const
{
	CPtr<IRegisteredTask> task;
	CPtr<ITaskDefinition> definiton;
	CPtr<ITriggerCollection> triggerCollection;
	CPtr<ITrigger> trigger;
	TASK_TRIGGER_TYPE2 type = TASK_TRIGGER_EVENT;
	if( FAILED(d->folder->GetTask( _bstr_t(TASK_NAME), &task )) ||
		FAILED(task->get_Definition(&definiton)) ||
		FAILED(definiton->get_Triggers( &triggerCollection )) ||
		FAILED(triggerCollection->get_Item(1, &trigger)) ||
		FAILED(trigger->get_Type(&type)) )
		return ScheduledUpdateTask::REMOVED;

	switch(type)
	{
	case TASK_TRIGGER_WEEKLY: return ScheduledUpdateTask::WEEKLY;
	case TASK_TRIGGER_MONTHLY: return ScheduledUpdateTask::MONTHLY;
	default: return ScheduledUpdateTask::DAILY;
	}
}

bool ScheduledUpdateTask::remove()
{
	return d->service && SUCCEEDED(d->folder->DeleteTask( _bstr_t(TASK_NAME), 0 ));
}
