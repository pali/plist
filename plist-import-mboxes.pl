#!/usr/bin/perl
#    PList - software for archiving and formatting emails from mailing lists
#    Copyright (C) 2014  Pali Rohár <pali.rohar@gmail.com>
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

use FindBin qw($Bin);
use lib $Bin;

use PList::Index;

sub help() {

	print "help:\n";
	print "<dir> <mbox1> [<mbox2> ...] [silent]\n";
	exit 1;

}

my $indexdir = shift @ARGV;
help() unless $indexdir;

my $silent;
if ( @ARGV and $ARGV[-1] eq "silent" ) {
	$silent = "silent";
	pop(@ARGV);
}

my @mboxes = @ARGV;
help() unless @mboxes;

my $index = PList::Index->new($indexdir, "$Bin/templates");
die "Error: Cannot open index dir '$indexdir'\n" unless $index;

$index = undef;

my %timestamps;

if ( open(my $file, "<", "$indexdir/timestamps") ) {
	while (<$file>) {
		chomp($_);
		my ($time, $file) = split(" ", $_, 2);
		next unless $time and $file;
		$timestamps{$file} = $time;
	}
}

my $count = 0;

foreach my $mbox (@mboxes) {
	if ( not -f $mbox ) {
		warn "Error: File '$mbox' does not exist\n";
		next;
	}
	my $time = (stat($mbox))[9];
	if ( not exists $timestamps{$mbox} or $timestamps{$mbox} < $time ) {
		my $script = "$Bin/plist.pl";
		my @args = ("index", "add-mbox", $indexdir, $mbox);
		push(@args, $silent) if defined $silent;
		my $ret = system($script, @args);
		if ( $ret == 0 ) {
			$timestamps{$mbox} = $time;
			$count++;
		}
	}
}

print "Processed $count mboxes\n";

if ( $count ) {
	my $file;
	if ( open(my $file, ">", "$indexdir/timestamps") ) {
		print $file $timestamps{$_} . " $_\n" foreach sort keys %timestamps;
		close($file);
	} else {
		warn "Error: Cannot store mbox timestamps\n";
	}
}
