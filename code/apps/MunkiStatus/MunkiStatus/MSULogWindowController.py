# -*- coding: utf-8 -*-
#
#  MSULogWindowController.py
#  MunkiStatus
#
#  Created by Greg Neagle on 4/18/16.
#  Copyright (c) 2016 Munki Project. All rights reserved.
#
#  Much code borrowed from https://github.com/MagerValp/LoginLog
#  with the blessing of MagerValp
#

from objc import YES, NO, IBAction, IBOutlet
from Foundation import *
from AppKit import *

import munki
import os


class MSULogViewDataSource(NSObject):
    
    """Data source for an NSTableView that displays an array of text lines.\n"""
    """Line breaks are assumed to be LF, and partial lines from incremental """
    """reading is handled."""
    
    logFileData = NSMutableArray.alloc().init()
    filteredData = logFileData
    
    lastLineIsPartial = False
    filter = ''
    
    def applyFilterToData(self):
        if len(self.filter):
            filterPredicate = NSPredicate.predicateWithFormat_('self CONTAINS[cd] %@', self.filter)
            self.filteredData = self.logFileData.filteredArrayUsingPredicate_(filterPredicate)
        else:
            self.filteredData = self.logFileData

    def addLine_partial_(self, line, isPartial):
        if self.lastLineIsPartial:
            joinedLine = self.logFileData.lastObject() + line
            self.logFileData.removeLastObject()
            self.logFileData.addObject_(joinedLine)
        else:
            self.logFileData.addObject_(line)
        self.lastLineIsPartial = isPartial
        self.applyFilterToData()
    
    def removeAllLines(self):
        self.logFileData.removeAllObjects()
    
    def lineCount(self):
        return self.filteredData.count()
    
    def numberOfRowsInTableView_(self, tableView):
        return self.lineCount()
    
    def tableView_objectValueForTableColumn_row_(self, tableView, column, row):
        if column.identifier() == 'data':
            return self.filteredData.objectAtIndex_(row)
        else:
            return ''


class MSULogWindowController(NSObject):
    
    window = IBOutlet()
    logView = IBOutlet()
    searchField = IBOutlet()
    pathControl = IBOutlet()
    
    logFileData = MSULogViewDataSource.alloc().init()
    
    fileHandle = None
    updateTimer = None
    
    _logData = NSMutableArray.alloc().init()
    
    @objc.accessor # PyObjC KVO hack
    def logData(self):
        return self._logData
    
    @objc.accessor # PyObjC KVO hack
    def setLogData_(self, newlist):
        self._logData = newlist
    
    @IBAction
    def searchFilterChanged_(self, sender):
        '''User changed the search field'''
        filterString = self.searchField.stringValue().lower()
        self.logFileData.filter = filterString
        self.logFileData.applyFilterToData()
        self.logView.reloadData()

    def getWindowLevel(self):
        '''Gets our NSWindowLevel. Works around issues with the loginwindow
        PolicyBanner in 10.11+ Some code based on earlier work by Pepijn
        Bruienne'''
        window_level = NSScreenSaverWindowLevel - 1
        # Get our Darwin major version
        darwin_vers = int(os.uname()[2].split('.')[0])
        have_policy_banner = False
        for test_file in ['/Library/Security/PolicyBanner.txt',
                          '/Library/Security/PolicyBanner.rtf',
                          '/Library/Security/PolicyBanner.rtfd']:
            if os.path.exists(test_file):
                have_policy_banner = True
                break
        # bump our NSWindowLevel if we have a PolicyBanner in ElCap+
        if have_policy_banner and darwin_vers > 14:
            window_level = NSScreenSaverWindowLevel
        return window_level

    @IBAction
    def showLogWindow_(self, notification):
        # Show the log window.
        
        consoleuser = munki.getconsoleuser()
        if consoleuser == None or consoleuser == u"loginwindow":
            self.window.setCanBecomeVisibleWithoutLogin_(True)
            self.window.setLevel_(self.getWindowLevel())

        screenRect = NSScreen.mainScreen().frame()
        windowRect = screenRect.copy()
        windowRect.origin.x = 100.0
        windowRect.origin.y = 200.0
        windowRect.size.width -= 200.0
        windowRect.size.height -= 300.0
        
        logfile = munki.pref('LogFile')
        self.pathControl.setURL_(NSURL.fileURLWithPath_(logfile))
        self.window.setTitle_(os.path.basename(logfile))
        self.window.setFrame_display_(windowRect, NO)
        self.window.makeKeyAndOrderFront_(self)
        self.watchLogFile_(logfile)

    def watchLogFile_(self, logFile):
        # Display and continuously update a log file in the main window.
        self.stopWatching()
        self.logFileData.removeAllLines()
        self.logView.setDataSource_(self.logFileData)
        self.logView.reloadData()
        self.fileHandle = NSFileHandle.fileHandleForReadingAtPath_(logFile)
        self.refreshLog()
        # Kick off a timer that updates the log view periodically.
        self.updateTimer = NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            0.25, self, u"refreshLog", None, YES)
    
    def stopWatching(self):
        # Release the file handle and stop the update timer.
        if self.fileHandle is not None:
            self.fileHandle.closeFile()
            self.fileHandle = None
        if self.updateTimer is not None:
            self.updateTimer.invalidate()
            self.updateTimer = None
    
    def refreshLog(self):
        # Check for new available data, read it, and scroll to the bottom.
        data = self.fileHandle.availableData()
        if data.length():
            utf8string = NSString.alloc().initWithData_encoding_(
                data, NSUTF8StringEncoding)
            for line in utf8string.splitlines(True):
                if line.endswith(u"\n"):
                    self.logFileData.addLine_partial_(line.rstrip(u"\n"), False)
                else:
                    self.logFileData.addLine_partial_(line, True)
            self.logView.reloadData()
            self.logView.scrollRowToVisible_(self.logFileData.lineCount() - 1)

    def windowWillClose_(self, notification):
        self.stopWatching()
