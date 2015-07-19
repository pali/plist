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

package PList::Email;

use strict;
use warnings;

sub new($) {

	my ($class) = @_;

	my %parts;
	my %headers;

	my $self = {
		parts => \%parts,
		headers => \%headers,
	};

	return bless $self, $class;

}

sub id($) {

	my ($self) = @_;
	return ${${$self->{headers}}{0}}{id};

}

sub part($$) {

	my ($self, $part) = @_;
	return ${$self->{parts}}{$part};

}

sub parts($) {

	my ($self) = @_;
	return $self->{parts};

}

sub header($$) {

	my ($self, $part) = @_;
	return ${$self->{headers}}{$part};

}

sub headers($) {

	my ($self) = @_;
	return $self->{headers};

}

sub data($$;$) {

	die;

}

sub add_part($$) {

	my ($self, $part) = @_;
	${$self->{parts}}{$part->{part}} = $part;

}

sub add_header($$) {

	my ($self, $header) = @_;
	${$self->{headers}}{$header->{part}} = $header;

}

sub add_data($$$) {

	die;

}

1;
