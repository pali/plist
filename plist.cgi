#!/usr/bin/perl

use strict;
use warnings;

use PList::Index;
use PList::Email::Binary;

use CGI;
use Time::Piece;

binmode(\*STDOUT, ":utf8");

my $q = new CGI;

$q->charset("utf-8");

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

my $address_template = <<END;
<a href='?indexdir=$indexdir&action=search&name=<TMPL_VAR ESCAPE=URL NAME=NAME>'><TMPL_VAR ESCAPE=HTML NAME=NAME></a> <a href='?indexdir=$indexdir&action=search&email=<TMPL_VAR ESCAPE=URL NAME=EMAIL>'>&lt;<TMPL_VAR ESCAPE=HTML NAME=EMAIL>&gt;</a>
END

my $subject_template = <<END;
<a href='?indexdir=$indexdir&action=get-tree&id=<TMPL_VAR ESCAPE=URL NAME=ID>'><TMPL_VAR ESCAPE=HTML NAME=SUBJECT></a>
END

my $download_template = <<END;
<b><a href='?indexdir=$indexdir&action=get-part&id=<TMPL_VAR ESCAPE=URL NAME=ID>&part=<TMPL_VAR ESCAPE=URL NAME=PART>'>Download</a></b>
END

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
	my $desc = $q->param("desc");
	my $limitup = $q->param("limitup");
	my $limitdown = $q->param("limitdown");

	if ( not $id ) {
		print $q->header(-status => 404);
		exit;
	}

	if ( $desc and $desc == 1 ) {
		$desc = 1;
	} else {
		$desc = 0;
	}

	my $email = $index->db_email($id);
	if ( not $email ) {
		print $q->header(-status => 404);
		exit;
	}
	$id = $email->{id};

	my $tree = $index->db_tree($id, $desc, 1, $limitup, $limitdown);
	if ( not $email ) {
		print $q->header(-status => 404);
		exit;
	}
	my $root = ${$tree->{root}}[0];
	delete $tree->{root};

	print $q->header();
	print $q->start_html(-title => "Tree for $id");

	print "<ul class='tree'>\n";

	my %processed = ($root => 1);
	my @stack = ([$root, 0]);
	my $prevlen = 0;

	while ( @stack ) {

		my $m = pop(@stack);
		my ($tid, $len) = @{$m};
		my $down = $tree->{$tid};

		while ( $prevlen > $len ) {
			print "</ul>\n</li>\n";
			--$prevlen;
		}

		my $email = $index->db_email($tid, 1);
		my $mid = $q->escapeHTML($email->{messageid});
		my $subject = $q->escapeHTML($email->{subject});
		my $from = "unknown";

		if ( @{$email->{from}} ) {
			$from = $q->escapeHTML(${${$email->{from}}[0]}[1] . " <" . ${${$email->{from}}[0]}[0] . ">");
		}

		print "<li>";
		print "<a href='?indexdir=$indexdir&action=gen-html&id=$mid'>$subject</a> - $from";

		my $count = 0;

		if ( $down ) {
			foreach ( @{$down} ) {
				if ( not $processed{$_} ) {
					++$count;
					$processed{$_} = 1;
					push(@stack, [$_, $len+1]);
				}
			}
		}

		if ( $count ) {
			print "\n<ul>\n";
		} else {
			print "</li>\n";
		}

		$prevlen = $len;

	}

	while ( $prevlen ) {
		print "</ul>\n</li>\n";
		--$prevlen;
	}

	print "</ul>";

	print $q->end_html();

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
	if ( not $roots ) {
		print $q->header(-status => 404);
		exit;
	}

	print $q->header();
	print $q->start_html(-title => "Roots");
	print $q->start_table();
	print "\n";
	print $q->Tr($q->td(["<a href='?indexdir=$indexdir&action=get-tree&id=" . $q->escapeHTML(${$_}[1]) . "'>" . $q->escapeHTML(${$_}[1]) . "</a>"])) . "\n" foreach @{$roots};
	print $q->end_table();
	print $q->end_html();

} elsif ( $action eq "gen-html" ) {

	my %config = (address_template => \$address_template, subject_template => \$subject_template, download_template => \$download_template);

	my $id = $q->param("id");
	if ( not $id ) {
		print $q->header(-status => 404);
		exit;
	}
	my $str = $index->view($id, %config);
	if ( not $str ) {
		print $q->header(-status => 404);
		exit;
	}
	print $q->header();
	print $str;

} elsif ( $action eq "search" ) {

	my $subject = $q->param("subject");
	my $email = $q->param("email");
	my $name = $q->param("name");
	my $type = $q->param("type");
	my $date1 = $q->param("date1");
	my $date2 = $q->param("date2");
	my $limit = $q->param("limit");
	my $offset = $q->param("offset");
	my $desc = $q->param("desc");

	my %args;
	$args{subject} = $subject if $subject;
	$args{email} = $email if $email;
	$args{name} = $name if $name;
	$args{type} = $type if defined $type;
	$args{date1} = $date1 if defined $date1;
	$args{date2} = $date2 if defined $date2;
	$args{limit} = $limit if defined $limit;
	$args{offset} = $offset if defined $offset;
	$args{desc} = $desc if defined $desc;

	my $ret = $index->db_emails(%args);
	if ( not $ret ) {
		print $q->header(-status => 404);
		exit;
	}

	print $q->header();
	print $q->start_html(-title => "Search");
	print $q->start_table();
	print "\n";

	foreach ( @{$ret} ) {
		my $id = ${$_}[1];
		my $date = ${$_}[2];
		my $subject = ${$_}[3];
		my $line = "<a href='?indexdir=$indexdir&action=gen-html&id=" . $q->escapeHTML($id) . "'>" . $q->escapeHTML($subject) . "</a> - " . $q->escapeHTML(localtime($date)->strftime("%Y-%m-%d %H:%M:%S %z"));
		print $q->Tr($q->td($line)) . "\n";
	}

	print $q->end_table();
	print $q->end_html();

} else {

	print $q->header(-status => 404);

}
