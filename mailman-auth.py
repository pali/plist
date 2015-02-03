#!/usr/bin/python

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
