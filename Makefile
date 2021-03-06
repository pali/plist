#    PList - software for archiving and formatting emails from mailing lists
#    Copyright (C) 2014-2015  Pali Rohár <pali.rohar@gmail.com>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License along
#    with this program; if not, write to the Free Software Foundation, Inc.,
#    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

PREFIX := /usr
DESTDIR :=

TARGET := $(DESTDIR)$(PREFIX)

SCRIPTS := plist.pl plist-import-mboxes.pl
EFILES := mailman-auth.py mailman-auth.pl plist.cgi
FILES := COPYING README .htaccess apache.conf mm_cfg.py
DIRS := Email PList templates

all:

clean:

install:
	mkdir -p "$(TARGET)/share/plist/"
	mkdir -p "$(TARGET)/bin/"
	for script in $(SCRIPTS); do \
		install -p -m 755 $$script "$(TARGET)/share/plist/"; \
		printf '%s\n%s "%s" "%s"\n' "#!/bin/sh" "exec" "$(PREFIX)/share/plist/$$script" '$$@' > "$(TARGET)/bin/$$script"; \
		chmod 755 "$(TARGET)/bin/$$script"; \
		touch -r "$(TARGET)/share/plist/$$script" "$(TARGET)/bin/$$script"; \
	done
	for file in $(EFILES); do \
		install -p -m 755 $$file "$(TARGET)/share/plist/"; \
	done
	for file in $(FILES); do \
		install -p -m 644 $$file "$(TARGET)/share/plist/"; \
	done
	for dir in $(DIRS); do \
		cp -a "$$dir" "$(TARGET)/share/plist/"; \
	done
