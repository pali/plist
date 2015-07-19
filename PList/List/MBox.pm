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

package PList::List::MBox;

use strict;
use warnings;

use base "PList::List";

use PList::Email::MIME;

use Email::Folder::Mbox 0.859;

sub new($$;$) {

	my ($class, $arg, $unescape) = @_;

	my $is_fh = 0;
	{
		$@ = "";
		my $fd = eval { fileno $arg; };
		$is_fh = !$@ && defined $fd;
	}

	my @args;

	if ( $is_fh ) {
		push(@args, "FH");
		push(@args, fh => $arg);
	} else {
		push(@args, $arg);
	}

	# NOTE: When jwz_From_ is set to 1 message separator is string "^From "
	push(@args, jwz_From_ => 1);

	if ( $unescape ) {
		# NOTE: When unescape is set to 1 every "^>+From " line is unescaped
		push(@args, unescape => 1);
	}

	my $mbox = Email::Folder::Mbox->new(@args);
	return undef unless ref $mbox;

	return bless \$mbox, $class;

}

sub eof($) {

	my ($mbox) = @_;

	return 0 unless ${$mbox}->{_fh};
	return eof(${$mbox}->{_fh});

}

sub readnext($) {

	my ($mbox) = @_;

	my $from = ${$mbox}->next_from();
	my $message = ${$mbox}->next_messageref();
	my $messageid = ${$mbox}->messageid();

	return PList::Email::MIME::from_str($message, $from, $messageid);

}

1;
