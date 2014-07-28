#!/usr/bin/perl

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

my $index = new PList::Index($indexdir);
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
