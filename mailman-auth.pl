#!/usr/bin/perl
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

use strict;
use warnings;

use Encode qw(encode_utf8);
use CGI::Simple::Util qw(escape);

my $indexdir = escape(encode_utf8($ENV{INDEX_DIR}));
my $authuser = escape(encode_utf8($ENV{REMOTE_USER}));
my $authpass = escape(encode_utf8($ENV{REMOTE_PASSWORD}));

if ( not defined $indexdir or not length $indexdir ) {
	warn "Variable INDEX_DIR is empty\n";
	exit 1;
}

if ( not defined $authuser or not length $authuser ) {
	warn "Variable REMOTE_USER is empty\n";
	exit 1;
}

if ( not defined $authpass or not length $authpass ) {
	warn "Variable REMOTE_PASSWORD is empty\n";
	exit 1;
}

%ENV = ();
$ENV{PATH_INFO} = "/$indexdir";
$ENV{REQUEST_METHOD} = "GET";
$ENV{QUERY_STRING} = "email=$authuser&password=$authpass";

my $output = `/usr/lib/cgi-bin/mailman/options`;
my $status = $?;

if ( $status == -1 ) {
	warn "Cannot execute mailman cgi script: $!\n";
	exit 1;
} elsif ( ($status >> 8) != 0 ) {
	warn "Mailman cgi script failed\n";
	exit 1;
}

if ( $output =~ /^Status:\s*401/ ) {
	warn "Authentication failed for $authuser\n";
	exit 1;
}

if ( $output =~ /^Status:\s*404/ ) {
	warn "No such list $indexdir\n";
	exit 1;
}

if ( $output =~ /^Set-Cookie:/ ) {
	exit 0;
}

warn "Unknown error, authentication probably failed for $authuser\n";
exit 1;
