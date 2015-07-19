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

package PList::Template;

use strict;
use warnings;

use Encode qw(encode_utf8);
use HTML::Template;

sub new($$;$) {

	my ($class, $arg, $dir) = @_;

	my @args = (die_on_bad_params => 0, utf8 => 1, loop_context_vars => 1);

	if ( ref $arg ) {
		push(@args, scalarref => $arg);
	} else {
		push(@args, filename => $arg);
		push(@args, path => $dir);
	}

	my $template = HTML::Template->new(@args);
	return bless \$template, $class;

}

sub param($$$) {

	my ($self, $param, $value) = @_;
	# NOTE: Bug in HTML::Template: Attribute ESCAPE=URL working only on encoded utf8 string. But attribute ESCAPE=HTML working on normal utf8 string
	$value = encode_utf8($value) if $param =~ /URL$/;
	return ${$self}->param($param, $value);

}

sub output($) {

	my ($self) = @_;
	return ${$self}->output();

}

1;
