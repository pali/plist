#!/usr/bin/python
#    PList - software for archiving and formatting emails from mailing lists
#    Copyright (C) 2015  Pali Rohár <pali.rohar@gmail.com>
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

import sys
import os

sys.path.append('/usr/lib/mailman/')

from Mailman import mm_cfg
from Mailman import Errors
from Mailman import MailList

listname = os.getenv('INDEX_DIR')
username = os.getenv('REMOTE_USER')
password = os.getenv('REMOTE_PASSWORD')

if not listname:
    sys.stderr.write('Variable INDEX_DIR is empty\n')
    sys.exit(1)

if not username:
    sys.stderr.write('Variable REMOTE_USER is empty\n')
    sys.exit(1)

if not password:
    sys.stderr.write('Variable REMOTE_PASSWORD is empty\n')
    sys.exit(1)

try:
    mlist = MailList.MailList(listname, lock=0)
except Errors.MMListError, e:
    sys.stderr.write('No such list "' + listname + '": ' + str(e) + '\n')
    sys.exit(1)
except IOError, e:
    sys.stderr.write('No such list "' + listname + '": ' + str(e) + '\n')
    sys.exit(1)
except:
    e = sys.exc_info()[0]
    sys.stderr.write('No such list "' + listname + '": ' + str(e) + '\n')
    sys.exit(1)

ac = mlist.Authenticate((mm_cfg.AuthUser, mm_cfg.AuthListModerator, mm_cfg.AuthListAdmin, mm_cfg.AuthSiteAdmin), password, username)
if not ac:
    sys.stderr.write('Authentication failed for "' + username + '"\n')
    sys.exit(1)

sys.exit(0)
