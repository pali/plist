#!/usr/bin/perl

use strict;
use warnings;

use PList::Index;
use PList::Email::Binary;

use CGI qw(-no_xhtml -utf8);
use Time::Piece;

binmode(\*STDOUT, ":utf8");

my $q = new CGI;

$q->charset("utf-8");

my @html_params = (-lang => "", -head => $q->meta({-http_equiv => "Content-Type", -content => "text/html; charset=utf-8"}));

my $indexdir = $q->param("indexdir");

if ( not $indexdir ) {

	# List all directories in current directory

	my $dh;
	if ( not opendir($dh, ".") ) {
		print $q->header(-status => 404);
		exit;
	}

	print $q->header();
	print $q->start_html(@html_params, -title => "PList");

	print "<ul>\n";

	while ( defined (my $name = readdir($dh)) ) {
		next if $name =~ /^\./;
		next unless -d $name;
		next unless -f "$name/config";
		$name = $q->escape($name);
		print "<li><a href='?indexdir=$name'>$name</a></li>\n";
	}

	closedir($dh);

	print "</ul>";
	print $q->end_html();

	exit;

}

my $eindexdir = $q->escape($indexdir);

my $action = $q->param("action");

if ( not $action ) {

	# Show info page

	print $q->header();
	print $q->start_html(@html_params, -title => $indexdir);
	print "<ul>\n";
	print "<li><a href='?indexdir=$eindexdir&amp;action=get-roots'>Show all roots</a></li>\n";
	print "<li><a href='?indexdir=$eindexdir&amp;action=search&amp;limit=100&amp;desc=1'>Show last 100 emails</a></li>\n";
	print "<li><a href='?indexdir=$eindexdir&amp;action=search'>Search</a></li>\n";
	print "</ul>";
	print $q->end_html();

	exit;

}

my $index = new PList::Index($indexdir);
if ( not $index ) {
	print $q->header(-status => 404);
	exit;
}

my $address_template = <<END;
<a href='?indexdir=$eindexdir&amp;action=search&amp;name=<TMPL_VAR ESCAPE=URL NAME=NAME>'><TMPL_VAR ESCAPE=HTML NAME=NAME></a> <a href='?indexdir=$eindexdir&amp;action=search&amp;email=<TMPL_VAR ESCAPE=URL NAME=EMAIL>'>&lt;<TMPL_VAR ESCAPE=HTML NAME=EMAIL>&gt;</a>
END

my $subject_template = <<END;
<a href='?indexdir=$eindexdir&amp;action=get-tree&amp;id=<TMPL_VAR ESCAPE=URL NAME=ID>'><TMPL_VAR ESCAPE=HTML NAME=SUBJECT></a>
END

my $download_template = <<END;
<b><a href='?indexdir=$eindexdir&amp;action=get-part&amp;id=<TMPL_VAR ESCAPE=URL NAME=ID>&amp;part=<TMPL_VAR ESCAPE=URL NAME=PART>'>Download</a></b>
END

my $imagepreview_template = <<END;
<img src='?indexdir=$eindexdir&amp;action=get-part&amp;id=<TMPL_VAR ESCAPE=URL NAME=ID>&amp;part=<TMPL_VAR ESCAPE=URL NAME=PART>'>
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
	my $date = $pemail->header("0")->{date};
	my $size = $pemail->part($part)->{size};
	my $mimetype = $pemail->part($part)->{mimetype};
	my $filename = $pemail->part($part)->{filename};
	eval { $date = Time::Piece->strptime($date, "%Y-%m-%d %H:%M:%S %z") };
	$date = $date->strftime("%a, %d %b %Y %H:%M:%S GMT") if $date; # TODO: check if timezone is really converted to GMT by Time::Piece
	$mimetype = "application/octet-stream" unless $mimetype;
	$filename = "File-$part.bin" unless $filename;
	$q->charset("") unless $mimetype =~ /^text\//;
	print $q->header(-type => $mimetype, -attachment => $filename, -expires => "+10y", last_modified => $date, -content_length => $size);
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
	if ( not $tree ) {
		print $q->header(-status => 404);
		exit;
	}
	my $root = ${$tree->{root}}[0];
	delete $tree->{root};

	print $q->header();
	print $q->start_html(@html_params, -title => "Tree for " . $email->{messageid});

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
		my $mid = $q->escape($email->{messageid});
		my $subject = $q->escapeHTML($email->{subject});
		my $date;
		my $from;

		if ( $email->{date} ) {
			$date = $q->escapeHTML(localtime($email->{date})->strftime("%Y-%m-%d %H:%M:%S %z"));
		}

		if ( @{$email->{from}} ) {
			$from = "<a href='?indexdir=$eindexdir&amp;action=search&amp;name=" . $q->escape(${${$email->{from}}[0]}[1]) . "'>" . $q->escapeHTML(${${$email->{from}}[0]}[1]) . "</a> <a href='?indexdir=$eindexdir&amp;action=search&amp;email=" . $q->escape(${${$email->{from}}[0]}[0]) . "'>&lt;" . $q->escapeHTML(${${$email->{from}}[0]}[0]) . "&gt;</a>";
		}

		print "<li>";

		if ( not $subject and not $from and not $date ) {
			print "unknown";
		} else {
			$subject = "unknown" unless $subject;
			$from = "unknown" unless $from;
			$date = "unknown" unless $date;
			print "<a href='?indexdir=$eindexdir&amp;action=gen-html&amp;id=$mid'>$subject</a> - $from - $date";
		}

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
	print $q->start_html(@html_params, -title => "Roots");
	print "<ul>\n";

	foreach ( @{$roots} ) {
		print "<li><a href='?indexdir=$eindexdir&amp;action=get-tree&amp;id=" . $q->escape(${$_}[1]) . "'>" . $q->escapeHTML(${$_}[1]) . "</a></li>\n";
	}

	print "</ul>";
	print $q->end_html();

} elsif ( $action eq "gen-html" ) {

	my %config = (address_template => \$address_template, subject_template => \$subject_template, download_template => \$download_template, imagepreview_template => \$imagepreview_template);

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
	my $size;
	{
		use bytes;
		$size = length($str);
	}
	print $q->header(-content_length => $size);
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
	my $showtree = $q->param("showtree");

	my %args;
	$args{subject} = $subject if defined $subject and length $subject;
	$args{email} = $email if defined $email and length $email;
	$args{name} = $name if defined $name and length $name;
	$args{type} = $type if defined $type and length $type;
	$args{date1} = $date1 if defined $date1 and length $date1;
	$args{date2} = $date2 if defined $date2 and length $date2;
	$args{limit} = $limit if defined $limit and length $limit;
	$args{offset} = $offset if defined $offset and length $offset;
	$args{desc} = $desc if defined $desc and length $desc;

	if ( not keys %args ) {

		# Show search formular

		print $q->header();
		print $q->start_html(@html_params, -title => "Search");
		print $q->start_form(-method => "GET", -action => "?");
		print $q->hidden(-name => "indexdir", -default => $indexdir) . "\n";
		print "subject: " . $q->textfield(-name => "subject") . "<br>\n";
		print "email: " . $q->textfield(-name => "email") . "<br>\n";
		print "name: " . $q->textfield(-name => "name") . "<br>\n";
		print "type: " . $q->textfield(-name => "type") . "<br>\n";
		print "date1: " . $q->textfield(-name => "date1") . "<br>\n";
		print "date2: " . $q->textfield(-name => "date2") . "<br>\n";
		print "limit: " . $q->textfield(-name => "limit") . "<br>\n";
		print "offset: " . $q->textfield(-name => "offset") . "<br>\n";
		print "desc: " . $q->textfield(-name => "desc") . "<br>\n";
		print "showtree: " . $q->textfield(-name => "showtree") . "<br>\n";
		print $q->submit(-name => "action", -value => "search") . "<br>\n";
		print $q->end_form();
		print $q->end_html();

		exit;
	}

	my $ret = $index->db_emails(%args);
	if ( not $ret ) {
		print $q->header(-status => 404);
		exit;
	}

	print $q->header();
	print $q->start_html(@html_params, -title => "Search");
	print "<ul>\n";

	if ( $showtree ) {

		my %processed;

		foreach ( @{$ret} ) {
			my $rid = ${$_}[0];
			next if $processed{$rid};
			$processed{$rid} = 1;
			my $tree = $index->db_tree($rid, $desc, 1, 1, 1);

			my $root = ${$tree->{root}}[0];
			delete $tree->{root};

			print "<ul class='tree'>\n";

			my %processed = ($root => 1);
#			$processed{$root} = 1;
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
				my $mid = $q->escape($email->{messageid});
				my $subject = $q->escapeHTML($email->{subject});
				my $date;
				my $from;

				if ( $email->{date} ) {
					$date = $q->escapeHTML(localtime($email->{date})->strftime("%Y-%m-%d %H:%M:%S %z"));
				}

				if ( @{$email->{from}} ) {
					$from = "<a href='?indexdir=$eindexdir&amp;action=search&amp;name=" . $q->escape(${${$email->{from}}[0]}[1]) . "'>" . $q->escapeHTML(${${$email->{from}}[0]}[1]) . "</a> <a href='?indexdir=$eindexdir&amp;action=search&amp;email=" . $q->escape(${${$email->{from}}[0]}[0]) . "'>&lt;" . $q->escapeHTML(${${$email->{from}}[0]}[0]) . "&gt;</a>";
				}

				print "<li>";

				if ( not $subject and not $from and not $date ) {
					print "unknown";
				} else {
					$subject = "unknown" unless $subject;
					$from = "unknown" unless $from;
					$date = "unknown" unless $date;
					print "<a href='?indexdir=$eindexdir&amp;action=gen-html&amp;id=$mid'>$subject</a> - $from - $date";
				}

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


		}

	} else {

		foreach ( @{$ret} ) {
			my $id = ${$_}[1];
			my $date = ${$_}[2];
			my $subject = ${$_}[3];
			print "<li>";
			print "<a href='?indexdir=$eindexdir&amp;action=gen-html&amp;id=" . $q->escape($id) . "'>" . $q->escapeHTML($subject) . "</a> - ";
			print $q->escapeHTML(localtime($date)->strftime("%Y-%m-%d %H:%M:%S %z"));
			print "</li>\n";
		}

	}

	print "</ul>";
	print $q->end_html();

} else {

	print $q->header(-status => 404);

}
