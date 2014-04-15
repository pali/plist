#!/usr/bin/perl

use strict;
use warnings;

use PList::Index;
use PList::Email::Binary;

use CGI qw(-no_xhtml -utf8);
use Time::Piece;

binmode(\*STDOUT, ":utf8");

# global variables
my $q;
my $script;
my $indexdir;
my $action;

sub print_start_html($;$@) {
	my ($title, $noh2, @header) = @_;
	print $q->header(@header);
	print $q->start_html(-lang => "", -head => $q->meta({-http_equiv => "Content-Type", -content => "text/html; charset=utf-8"}), -title => $title);
	print $q->h2($q->escapeHTML($title)) . "\n" unless $noh2;
}

sub print_p($) {
	my ($text) = @_;
	print $q->p($q->escapeHTML($text));
}

sub print_ahref($$;$) {
	my ($href, $text, $nobr) = @_;
	print $q->a({href => $href}, $q->escapeHTML($text));
	print $q->br() . "\n" unless $nobr;
}

sub error($) {
	my ($msg) = @_;
	print_start_html("Error 404", 1, -status => 404);
	print_p("Error: " . $msg);
	print $q->end_html();
	exit;
}

sub gen_url {
	my $action = shift;
	my $url = $script . "?indexdir=" . $q->escape($indexdir) . "&action=" . $q->escape($action);
	$url .= "&" . $q->escape(shift) . "=" . $q->escape(shift) while @_;
	return $url;
}

$q = new CGI;
$q->charset("utf-8");

$script = $q->url(-absolute => 1);
$indexdir = $q->param("indexdir");
$action = $q->param("action");

if ( not $indexdir ) {

	# List all directories in current directory

	my $dh;
	if ( not opendir($dh, ".") ) {
		error("Cannot open directory");
	}

	print_start_html("List of archives");
	print $q->start_p() . "\n";

	my $count = 0;

	while ( defined ($indexdir = readdir($dh)) ) {
		next if $indexdir =~ /^\./;
		next unless -d $indexdir;
		next unless -f "$indexdir/config";
		++$count;
		print_ahref(gen_url(""), $indexdir);
	}
	closedir($dh);

	print "(No archives)\n" unless $count;

	print $q->end_p();
	print $q->end_html();

	exit;

}

my $index = new PList::Index($indexdir);
error("Archive $indexdir does not exist") unless $index;

if ( not $action ) {

	# Show info page
	print_start_html("Archive $indexdir");
	print $q->start_p() . "\n";
	print_ahref(gen_url("browse", limit => 100), "Browse threads");
	print_ahref(gen_url("get-roots", limit => 100, desc => 1), "Browse roots of threads");
	print_ahref(gen_url("search", limit => 100, desc => 1), "Browse emails");
	print_ahref(gen_url("search"), "Search emails");
	print $q->br() . "\n";
	print_ahref("?", "Show list of archives");
	print $q->end_p();
	print $q->end_html();
	exit;

}

my $address_template = "<a href='" . gen_url("search", limit => 100, name => "") . "<TMPL_VAR ESCAPE=URL NAME=NAMEURL>'><TMPL_VAR ESCAPE=HTML NAME=NAME></a> <a href='" . gen_url("search", limit => 100, email => "") . "<TMPL_VAR ESCAPE=URL NAME=EMAILURL>'>&lt;<TMPL_VAR ESCAPE=HTML NAME=EMAIL>&gt;</a>";

my $subject_template = "<a href='" . gen_url("tree", id => "") . "<TMPL_VAR ESCAPE=URL NAME=ID>'><TMPL_VAR ESCAPE=HTML NAME=SUBJECT></a>";

my $download_template = "<b><a href='" . gen_url("download", id => "") . "<TMPL_VAR ESCAPE=URL NAME=ID>&amp;part=<TMPL_VAR ESCAPE=URL NAME=PART>'>Download</a></b>\n";

my $imagepreview_template = "<img src='" . gen_url("download", id => "") . "<TMPL_VAR ESCAPE=URL NAME=ID>&amp;part=<TMPL_VAR ESCAPE=URL NAME=PART>'>\n";

sub format_date($) {

	my ($date) = @_;
	$date = gmtime($date) if $date;
	# TODO: configure format
	$date = $date->strftime("%F %T %z") if $date;
	return $date if $date;
	return "";

}

sub print_tree($$$$$$) {

	my ($index, $id, $desc, $limitup, $limitdown, $processed) = @_;

	my $count = 0;

	my $tree = $index->db_tree($id, $desc, 1, $limitup, $limitdown);
	if ( not $tree ) {
		return 0;
	}
	my $root = ${$tree->{root}}[0];
	delete $tree->{root};

	$processed->{$root} = 1;
	my @stack = ([$root, 0]);

	while ( @stack ) {

		my $m = pop(@stack);
		my ($tid, $len) = @{$m};
		my $down = $tree->{$tid};

		if ( $down ) {
			foreach ( @{$down} ) {
				if ( not $processed->{$_} ) {
					$processed->{$_} = 1;
					push(@stack, [$_, $len+1]);
				}
			}
		}

		my $email = $index->db_email($tid, 1);

		#TODO: db_email can fail

		my $mid = $email->{messageid};
		my $subject = $email->{subject};
		my $date = format_date($email->{date});

		$count++;

		print $q->start_Tr();

		print $q->start_td();
		for (my $i = 0; $i < $len; ++$i) { print "&emsp;" }
		print "&bull;&nbsp;";
		if ( $subject ) {
			print_ahref(gen_url("view", id => $mid), $subject, 1);
		} else {
			print "unknown";
		}
		print $q->end_td();

		print $q->start_td();
		if ( @{$email->{from}} ) {
			# TODO: Fix this code, add needed checks
			print_ahref(gen_url("search", limit => 100, name => ${${$email->{from}}[0]}[1]), ${${$email->{from}}[0]}[1], 1);
			print " ";
			print_ahref(gen_url("search", limit => 100, email => ${${$email->{from}}[0]}[0]), "<" . ${${$email->{from}}[0]}[0] . ">", 1);
		} else {
			print "unknown";
		}
		print $q->end_td();

		print $q->start_td();
		if ( $date ) {
			print $q->escapeHTML($date);
		} else {
			print "unknown";
		}
		print $q->end_td();

		print $q->end_Tr() . "\n";

	}

	return $count;

}

if ( $action eq "get-bin" ) {

	my $id = $q->param("id");
	error("Param id was not specified") unless $id;
	my $pemail = $index->email($id);
	error("Email with $id does not exist in archive $indexdir") unless $pemail;
	print $q->header(-type => "application/octet-stream", -attachment => "$id.bin", -charset => "");
	binmode(\*STDOUT, ":raw");
	PList::Email::Binary::to_fh($pemail, \*STDOUT);

} elsif ( $action eq "download" ) {

	my $id = $q->param("id");
	error("Param id was not specified") unless $id;
	my $part = $q->param("part");
	error("Param part was not specified") unless $id;
	my $pemail = $index->email($id);
	error("Email with $id does not exist in archive $indexdir") unless $pemail;
	error("Part $part of email with $id does not exist in archive $indexdir") unless $pemail->part($part);
	my $date = $pemail->header("0")->{date};
	my $size = $pemail->part($part)->{size};
	my $mimetype = $pemail->part($part)->{mimetype};
	my $filename = $pemail->part($part)->{filename};
	$date = gmtime($date) if $date;
	$date = $date->strftime("%a, %d %b %Y %T GMT") if $date;
	$mimetype = "application/octet-stream" unless $mimetype;
	$filename = "File-$part.bin" unless $filename;
	$q->charset("") unless $mimetype =~ /^text\//;
	print $q->header(-type => $mimetype, -attachment => $filename, -expires => "+10y", last_modified => $date, -content_length => $size);
	binmode(\*STDOUT, ":raw");
	$pemail->data($part, \*STDOUT);

} elsif ( $action eq "tree" ) {

	my $id = $q->param("id");
	my $desc = $q->param("desc");

	error("Param id was not specified") unless $id;

	my $email = $index->db_email($id);
	error("Email with $id does not exist in archive $indexdir") unless $email;

	print_start_html("Tree for email $id");

	my $order = 0;
	$order = 1 unless $desc;
	$order = $q->a({href => gen_url("tree", id => $id, desc => $order)}, $order ? "(DESC)" : "(ASC)");

	print $q->start_table(-style => "white-space:nowrap") . "\n";
	print $q->Tr($q->th({-align => "left"}, ["Subject", "From", "Date $order"])) . "\n";

	my $count = print_tree($index, $email->{id}, $desc, undef, undef, {});

	print $q->end_table() . "\n";

	print_p("(No emails)") unless $count;

	print $q->br() . "\n";
	print_ahref(gen_url(""), "Show archive $indexdir");
	print_ahref("?", "Show list of archives");
	print $q->end_html();

} elsif ( $action eq "get-roots" ) {

	my $desc = $q->param("desc");
	my $date1 = $q->param("date1");
	my $date2 = $q->param("date2");
	my $limit = $q->param("limit");
	my $offset = $q->param("offset");

	$desc = 0 unless defined $desc and length $desc;
	$date1 = "" unless defined $date1;
	$date2 = "" unless defined $date2;
	$limit = "" unless defined $limit;
	$offset = 0 unless defined $offset and length $offset;

	my %args;
	$args{date1} = $date1 if length $date1;
	$args{date2} = $date2 if length $date2;
	$args{limit} = $limit+1 if length $limit;
	$args{offset} = $offset if length $offset;

	my $roots = $index->db_roots($desc, %args);
	error("Database error (db_roots)") unless $roots;

	my $order = 0;
	$order = 1 unless $desc;
	$order = $q->a({href => gen_url("get-roots", desc => $order, date1 => $date1, date2 => $date2, limit => $limit, offset => 0)}, $order ? "(DESC)" : "(ASC)");

	print_start_html("Roots of threads");
	print $q->start_table(-style => "white-space:nowrap") . "\n";
	print $q->Tr($q->th({-align => "left"}, ["Subject", "Date $order"])) . "\n";

	my $neednext;
	my $printbr = 1;
	my $count = 0;

	foreach ( @{$roots} ) {
		if ( $neednext ) {
			$printbr = 0;
			print $q->end_table() . "\n";
			print $q->br() . "\n";
			print_ahref(gen_url("get-roots", desc => $desc, date1 => $date1, date2 => $date2, limit => $limit, offset => ($offset + $limit)), "Show next page");
			last;
		}
		my $id = $_->{messageid};
		my $subject = $_->{subject};
		my $date = format_date($_->{date});
		$subject = "unknown" unless $subject;
		$date = "unknown" unless $date;
		print $q->start_Tr();
		print $q->start_td();
		print_ahref(gen_url("tree", id => $id), $subject, 1);
		print $q->end_td();
		print $q->start_td({style => "white-space:nowrap"});
		print $q->escapeHTML($date);
		print $q->end_td();
		print $q->end_Tr();
		print "\n";
		++$count;
		if ( length $limit and $count >= $limit ) {
			$neednext = 1;
		}
	}

	print $q->end_table() . "\n" if $printbr;

	print_p("(No emails)") unless $count;

	if ( length $limit and $offset >= $limit ) {
		print $q->br() . "\n" if $printbr;
		print_ahref(gen_url("get-roots", desc => $desc, date1 => $date1, date2 => $date2, limit => $limit, offset => ($offset - $limit)), "Show previous page");
	}

	print $q->br() . "\n";
	print_ahref(gen_url(""), "Show archive $indexdir");
	print_ahref("?", "Show list of archives");
	print $q->end_html();

} elsif ( $action eq "view" ) {

	my $id = $q->param("id");
	error("Param id was not specified") unless $id;

	my %config = (address_template => \$address_template, subject_template => \$subject_template, download_template => \$download_template, imagepreview_template => \$imagepreview_template);

	my $str = $index->view($id, %config);
	error("Email with $id does not exist in archive $indexdir") unless $str;

	my $size;
	{
		use bytes;
		$size = length($str);
	}

	print $q->header(-content_length => $size);
	print $str;

} elsif ( $action eq "browse" ) {

	my $group = $q->param("group");

	if ( not $group ) {
		print_start_html("Browse threads");
		print $q->start_p() . "\n";
		print_ahref(gen_url("browse", group => "none", limit => 100), "Browse all");
		print $q->br() . "\n";
		print $q->b("Browse year:") . $q->br() . "\n";
		my $years = $index->db_date("%Y");
		if ( $years ) {
			print_ahref(gen_url("browse", group => "month", year => $_->[0]), $_->[0]) foreach @{$years};
		} else {
			print "(No years)" . $q->br() . "\n";
		}
	} elsif ( $group eq "month" ) {
		my $year = $q->param("year");
		error("Param year was not specified") unless $year;
		print_start_html("Browse threads in year $year");
		print $q->start_p() . "\n";
		my $date1;
		eval { $date1 = Time::Piece->strptime("$year", "%Y"); } or do { $date1 = undef; };
		if ( $date1 ) {
			my $date2 = $date1->add_years(1)->epoch();
			$date1 = $date1->epoch();
			print_ahref(gen_url("browse", group => "none", date1 => $date1, date2 => $date2, limit => 100), "Browse all in year $year");
			print $q->br() . "\n";
		}
		print $q->b("Browse month:") . $q->br() . "\n";
		my $months = $index->db_date("%m", "%Y", $year);
		if ( $months ) {
			foreach ( @{$months} ) {
				my $month = $_->[0];
				my $date1;
				eval { $date1 = Time::Piece->strptime("$year $month", "%Y %m"); } or do { $date1 = undef; };
				next unless $date1;
				my $fullmonth = $date1->fullmonth();
				my $date2 = $date1->add_months(1)->epoch();
				$date1 = $date1->epoch();
				print_ahref(gen_url("browse", group => "day", year => $year, month => $month), $fullmonth);
			}
		} else {
			print "(No months)" . $q->br() . "\n";
		}
	} elsif ( $group eq "day" ) {
		my $year = $q->param("year");
		error("Param year was not specified") unless $year;
		my $month = $q->param("month");
		error("Param month was not specified") unless $month;
		print_start_html("Browse threads in year $year month $month");
		print $q->start_p() . "\n";
		my $date1;
		eval { $date1 = Time::Piece->strptime("$year $month", "%Y %m"); } or do { $date1 = undef; };
		if ( $date1 ) {
			my $date2 = $date1->add_months(1)->epoch();
			$date1 = $date1->epoch();
			print_ahref(gen_url("browse", group => "none", date1 => $date1, date2 => $date2, limit => 100), "Browse all in year $year month $month");
			print $q->br() . "\n";
		}
		print $q->b("Browse days:") . $q->br() . "\n";
		my $days = $index->db_date("%d", "%Y %m", "$year $month");
		if ( $days ) {
			foreach ( @{$days} ) {
				my $day = $_->[0];
				my $date1;
				eval { $date1 = Time::Piece->strptime("$year $month $day", "%Y %m %d"); } or do { $date1 = undef; };
				next unless $date1;
				my $date2 = ($date1 + 24*60*60)->epoch();
				$date1 = $date1->epoch();
				print_ahref(gen_url("browse", group => "none", date1 => $date1, date2 => $date2, limit => 100), $day);
			}
		} else {
			print "(No days)" . $q->br() . "\n";
		}
	} elsif ( $group eq "none" ) {
		my $date1 = $q->param("date1");
		my $date2 = $q->param("date2");
		my $limit = $q->param("limit");
		my $offset = $q->param("offset");
		my $desc = $q->param("desc");
		my $treedesc = $q->param("treedesc");

		$date1 = "" unless defined $date1;
		$date2 = "" unless defined $date2;
		$limit = "" unless defined $limit;
		$offset = 0 unless defined $offset and length $offset;
		$desc = 0 unless defined $desc and length $desc;
		$treedesc = 0 unless defined $treedesc and length $treedesc;

		my %args;
		$args{date1} = $date1 if length $date1;
		$args{date2} = $date2 if length $date2;
		$args{limit} = $limit+1 if length $limit;
		$args{offset} = $offset if $offset;

		my $roots = $index->db_roots($desc, %args);
		error("Database error (db_roots)") unless $roots;

		print_start_html("Browse threads");
		print $q->start_p() . "\n";

		my $order = 0;
		$order = 1 unless $desc;

		my $treeorder = 0;
		$treeorder = 1 unless $treedesc;

		$order = $q->a({href => gen_url("browse", group => "none", date1 => $date1, date2 => $date2, limit => $limit, offset => 0, desc => $order, treedesc => $treedesc)}, $order ? "(thr DESC)" : "(thr ASC)");
		$treeorder = $q->a({href => gen_url("browse", group => "none", date1 => $date1, date2 => $date2, limit => $limit, offset => $offset, desc => $desc, treedesc => $treeorder)}, $treeorder ? "(msg DESC)" : "(msg ASC)");

		print $q->start_table(-style => "white-space:nowrap") . "\n";
		print $q->Tr($q->th({-align => "left"}, ["Subject", "From", "Date $order $treeorder"])) . "\n";

		my %processed;
		my $neednext;
		my $printbr = 1;
		my $count = 0;
		my $iter = -1;

		foreach ( @{$roots} ) {
			++$iter;
			my $rid = $_->{id};
			next if $processed{$rid};
			if ( $neednext ) {
				$printbr = 0;
				print $q->end_table();
				print $q->br() . "\n";
				print_ahref(gen_url("browse", group => "none", date1 => $date1, date2 => $date2, limit => $limit, offset => ($offset + $iter), desc => $desc, treedesc => $treedesc), "Show next page");
				last;
			}
			$processed{$rid} = 1;
			my $ret = print_tree($index, $_->{id}, $treedesc, undef, undef, \%processed);
			print "\n" if $ret > 0;
			$count += $ret;
			if ( length $limit and $count >= $limit ) {
				$neednext = 1;
			}
		}

		print $q->end_table() if $printbr;

	} else {
		error("Unknown value for param group");
	}

	print $q->br() . "\n";
	print_ahref(gen_url(""), "Show archive $indexdir");
	print_ahref("?", "Show list of archives");
	print $q->end_p();
	print $q->end_html();

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
	my $submit = $q->param("submit");

	$subject = "" unless defined $subject;
	$email = "" unless defined $email;
	$name = "" unless defined $name;
	$type = "" unless defined $type;
	$date1 = "" unless defined $date1;
	$date2 = "" unless defined $date2;
	$limit = "" unless defined $limit;
	$offset = 0 unless defined $offset and length $offset;
	$desc = 0 unless defined $desc and length $desc;

	my %args;
	$args{subject} = $subject if length $subject;
	$args{email} = $email if length $email;
	$args{name} = $name if length $name;
	$args{type} = $type if length $type;
	$args{date1} = $date1 if length $date1;
	$args{date2} = $date2 if length $date2;
	$args{limit} = $limit+1 if length $limit;
	$args{offset} = $offset if $offset;
	$args{desc} = $desc if $desc;

	if ( not $submit and not keys %args ) {
		# Show search form
		print_start_html("Search");
		print $q->start_form(-method => "GET", -action => gen_url("search"), -accept_charset => "utf-8");
		print $q->start_table() . "\n";
		print $q->Tr($q->td(["Subject:", $q->textfield(-name => "subject")])) . "\n";
		print $q->Tr($q->td(["Header type:", $q->popup_menu("type", ["", "from", "to", "cc"], "", {"" => "(any)"})])) . "\n";
		print $q->Tr($q->td(["Name:", $q->textfield(-name => "name")])) . "\n";
		print $q->Tr($q->td(["Email address:", $q->textfield(-name => "email")])) . "\n";
		# TODO: Add date1 and date2
		print $q->Tr($q->td(["Limit results:", $q->popup_menu("limit", ["10", "20", "50", "100", "200", ""], "100", {"" => "(unlimited)"})])) . "\n";
		print $q->Tr($q->td(["Sort order:", $q->popup_menu("desc", ["0", "1"], "0", {"0" => "ascending", "1" => "descending"})])) . "\n";
		print $q->Tr($q->td($q->submit(-name => "submit", -value => "Search"))) . "\n";
		print $q->end_table() . "\n";
		print $q->end_form() . "\n";
		print $q->start_p() . "\n";
		print_ahref(gen_url(""), "Show archive $indexdir");
		print_ahref("?", "Show list of archives");
		print $q->end_p();
		print $q->end_html();
		exit;
	}

	$args{implicit} = 0;

	my $ret = $index->db_emails(%args);
	error("Database error (db_emails)") unless $ret;

	my $order = 0;
	$order = 1 unless $desc;
	$order = $q->a({href => gen_url("search", subject => $subject, email => $email, name => $name, type => $type, date1 => $date1, date2 => $date2, limit => $limit, offset => 0, desc => $order)}, $order ? "(DESC)" : "(ASC)");

	print_start_html("Search");
	print $q->start_table(-style => "white-space:nowrap") . "\n";
	print $q->Tr($q->th({-align => "left"}, ["Subject", "Date $order"])) . "\n";

	my $neednext;
	my $printbr = 1;
	my $count = 0;
	foreach ( @{$ret} ) {
		if ( $neednext ) {
			$printbr = 0;
			print $q->end_table() . "\n";
			print $q->br() . "\n";
			print_ahref(gen_url("search", subject => $subject, email => $email, name => $name, type => $type, date1 => $date1, date2 => $date2, limit => $limit, offset => ($offset + $limit), desc => $desc), "Show next page");
			last;
		}
		my $id = $_->{messageid};
		my $date = format_date($_->{date});
		my $subject = $_->{subject};
		$subject = "unknown" unless $subject;
		$date = "unknown" unless $date;
		print $q->start_Tr();
		print $q->start_td();
		print_ahref(gen_url("view", id => $id), $subject, 1);
		print $q->end_td();
		print $q->start_td({style => "white-space:nowrap"});
		print $q->escapeHTML($date);
		print $q->end_td();
		print $q->end_Tr();
		print "\n";
		++$count;
		if ( length $limit and $count >= $limit ) {
			$neednext = 1;
		}
	}

	print $q->end_table() . "\n" if $printbr;

	print_p("(No emails)") unless $count;

	if ( length $limit and $offset >= $limit ) {
		print $q->br() . "\n" if $printbr;
		print_ahref(gen_url("search", subject => $subject, email => $email, name => $name, type => $type, date1 => $date1, date2 => $date2, limit => $limit, offset => ($offset - $limit), desc => $desc), "Show previous page");
	}

	print $q->br() . "\n";
	print_ahref(gen_url(""), "Show archive $indexdir");
	print_ahref("?", "Show list of archives");
	print $q->end_html();

} else {

	error("Unknown value for param action");

}
