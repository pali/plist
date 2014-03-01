#!/usr/bin/perl

use strict;
use warnings;

use PList::Index;
use PList::Email::Binary;

use CGI;

my $q = new CGI;

$q->charset("UTF-8");

my $indexdir = $q->param("indexdir");
my $action = $q->param("action");

if ( not $indexdir or not $action ) {
	print $q->header(-status => 404);
	exit;
}

my $index = new PList::Index($indexdir);
if ( not $index ) {
	print $q->header(-status => 404);
	exit;
}

if ( $action eq "get-bin" ) {

	my $id = $q->param("id");
	if ( not $id ) {
		print $q->header(-status => 404);
		exit;
	}
	my $pemail = $index->email($id);
	if ( not $pemail ) {
		print $q->header(-status => 404);
		exit;
	}
	print $q->header(-type => "application/octet-stream", -attachment => "$id.bin", -charset => "");
	binmode(\*STDOUT, ":raw");
	PList::Email::Binary::to_fh($pemail, \*STDOUT);

} elsif ( $action eq "get-part" ) {

	my $id = $q->param("id");
	my $part = $q->param("part");
	if ( not $id or not $part ) {
		print $q->header(-status => 404);
		exit;
	}
	my $pemail = $index->email($id);
	if ( not $pemail or not $pemail->part($part) ) {
		print $q->header(-status => 404);
		exit;
	}
	my $filename = $pemail->part($part)->{filename};
	$filename = "File-$part.bin" unless $filename;
	print $q->header(-type => "application/octet-stream", -attachment => "$filename", -charset => "");
	binmode(\*STDOUT, ":raw");
	$pemail->data($part, \*STDOUT);

} elsif ( $action eq "get-tree" ) {

	my $id = $q->param("id");
	if ( not $id ) {
		print $q->header(-status => 404);
		exit;
	}

	# TODO

} elsif ( $action eq "get-roots" ) {

	my $desc = $q->param("desc");
	my $date1 = $q->param("date1");
	my $date2 = $q->param("date2");
	my $limit = $q->param("limit");
	my $offset = $q->param("offset");

	my %args;
	$args{date1} = $date1 if defined $date1;
	$args{date2} = $date2 if defined $date2;
	$args{limit} = $limit if defined $limit;
	$args{offset} = $offset if defined $offset;

	if ( $desc and $desc == 1 ) {
		$desc = 1;
	} else {
		$desc = 0;
	}

	my $roots = $index->db_roots($desc, %args);

	print $q->header();
	print $q->start_html(-title => "Roots");
	print $q->start_table();
	print "\n";

	if ( $roots ) {
		foreach ( @{$roots} ) {
			if ( $_ ) {
				print $q->Tr($q->td(["<a href='?action=get-tree&id=" . $q->escapeHTML(${$_}[1]) . "'>" . $q->escapeHTML(${$_}[1]) . "</a>"])) . "\n";
			}
		}
	}

	print $q->end_table();
	print $q->end_html();

} elsif ( $action eq "gen-html" ) {

	my $id = $q->param("id");
	if ( not $id ) {
		print $q->header(-status => 404);
		exit;
	}
	my $str = $index->view($id);
	if ( not $str ) {
		print $q->header(-status => 404);
		exit;
	}
	print $q->header();
	print $str;

} else {

	print $q->header(-status => 404);

}
