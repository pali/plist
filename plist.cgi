#!/usr/bin/perl

use strict;
use warnings;

use PList::Index;
use PList::Email::Binary;

use CGI qw(-no_xhtml -utf8 -oldstyle_urls);
use Time::Piece;

binmode(\*STDOUT, ":utf8");

# global variables
my $q;
my $script;
my $indexdir;
my $action;
my $id;
my $path;

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
	my $oldindexdir = $q->escape($indexdir);
	my $oldaction = $q->escape($action);
	my $oldid = $q->escape($id);
	my $oldpath = $q->escape($path);
	$oldpath =~ s/%2F/\//g;
	$oldpath =~ s/%5C/\\/g;
	my $newindexdir = $oldindexdir;
	my $newaction = $oldaction;
	my $newid = "";
	my $newpath = "";
	my $args = "?";
	while ( @_ ) {
		my $key = shift;
		my $value = shift;
		if ( $key eq "indexdir" ) {
			$newindexdir = $q->escape($value);
		} elsif ( $key eq "-indexdir" ) {
			$newindexdir = $value;
		} elsif ( $key eq "action" ) {
			$newaction = $q->escape($value);
		} elsif ( $key eq "-action" ) {
			$newaction = $value;
		} elsif ( $key eq "id" ) {
			$newid = $q->escape($value);
		} elsif ( $key eq "-id" ) {
			$newid = $value;
		} elsif ( $key eq "path" ) {
			$newpath = $q->escape($value);
			$newpath =~ s/%2F/\//g;
			$newpath =~ s/%5C/\\/g;
		} elsif ( $key eq "-path" ) {
			$newpath = $value;
		} elsif ( $key =~ /^-(.*)$/ ) {
			$args .= $1 . "=" . $value . "&" if length $value;
		} else {
			$args .= $q->escape($key) . "=" . $q->escape($value) . "&" if length $value;
		}
	}
	chop($args);
	$newindexdir = "" unless $newindexdir;
	$newaction = "" unless $newaction and $newindexdir;
	$newid = "" unless $newid and $newaction;
	$newpath = "" unless $newpath and $newid;
	if ( $newindexdir eq $oldindexdir and $newaction eq $oldaction and $newid eq $oldid and $newpath eq $oldpath ) {
		return "?" unless length($args);
		return $args;
	} else {
		$args = "/" . $args;
	}
	if ( $newindexdir eq $oldindexdir and $newaction eq $oldaction and $newid eq $oldid and length($newpath) and not length($oldpath) ) {
		return $newpath . $args if length($args);
		return $newpath;
	} elsif ( $newindexdir eq $oldindexdir and $newaction eq $oldaction and length($newid) and not length($oldid) ) {
		my $url = $newid;
		$url .= "/" . $newpath if length($newpath);
		$url .= $args if length($args);
		return $url;
	} elsif ( $newindexdir eq $oldindexdir and length($newaction) and not length($oldaction) ) {
		my $url = $newaction;
		$url .= "/" . $newid if length($newid);
		$url .= "/" . $newpath if length($newpath);
		$url .= $args if length($args);
		return $url;
	} elsif ( length($newindexdir) and not length($oldindexdir) ) {
		my $url = $newindexdir;
		$url .= "/" . $newaction if length($newaction);
		$url .= "/" . $newid if length($newid);
		$url .= "/" . $newpath if length($newpath);
		$url .= $args if length($args);
		return $url;
	} else {
		my $url = $script;
		$url .= "/" . $newindexdir if length($newindexdir);
		$url .= "/" . $newaction if length($newaction);
		$url .= "/" . $newid if length($newid);
		$url .= "/" . $newpath if length($newpath);
		$url .= $args if length($args);
		return $url;
	}
}

sub get_script_url() {
	my $uri = $q->unescape($q->request_uri()); # request uri is escaped
	return undef unless $uri;
	$uri =~ s/\?.*$//s; # remove query string
	$uri =~ s/\+/ /g; # there is no difference between unescaped space and plus chars
	my $path_info = $q->path_info();
	$path_info =~ s/\+/ /g; # be consistent with uri
	$uri =~ s/\Q$path_info\E$//; # remove path_info
	return $uri;
}

$q = new CGI;
$q->charset("utf-8");

$script = get_script_url();
($_, $indexdir, $action, $id, $path) = split(/(?<=\/)/, $q->path_info(), 5);

$indexdir = "" unless $indexdir;
$action = "" unless $action and $indexdir;
$id = "" unless $id and $action;
$path = "" unless $path and $id;

error("Missing '/' at the end of URL") if ( length $indexdir and not $indexdir =~ /\/$/ ) or ( length $action and not $action =~ /\/$/ ) or ( length $id and not $id =~ /\/$/ );

chop($indexdir) if $indexdir =~ /\/$/;
chop($action) if $action =~ /\/$/;
chop($id) if $id =~ /\/$/;
chop($path) if $path =~ /\/$/;

error("Invalid archive name $indexdir") if $indexdir =~ /[\\\/]/;

if ( not $indexdir ) {

	# List all directories in current directory

	my $dh;
	if ( not opendir($dh, ".") ) {
		error("Cannot open directory");
	}

	print_start_html("List of archives");
	print $q->start_p() . "\n";

	my $count = 0;

	while ( defined (my $name = readdir($dh)) ) {
		next if $name =~ /^\./;
		next unless -d $name;
		next unless -f "$name/config";
		++$count;
		print_ahref(gen_url(indexdir => $name), $name);
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
	my $description = $index->description();
	print_start_html("Archive $indexdir");
	print $q->start_p() . "\n";
	print $q->escapeHTML($description) . $q->br() . $q->br() . "\n" if $description;
	print_ahref(gen_url(action => "browse"), "Browse by year");
	print_ahref(gen_url(action => "search"), "Search emails");
	print_ahref(gen_url(action => "trees"), "Show all trees");
	print_ahref(gen_url(action => "emails"), "Show all emails");
	print_ahref(gen_url(action => "roots"), "Show all roots of emails");
	print $q->start_form(-method => "GET", -action => gen_url(action => "search"), -accept_charset => "utf-8");
	print $q->textfield(-name => "str") . "\n";
	print $q->submit(-name => "submit", -value => "Quick Search") . "\n";
	print $q->end_form() . "\n";
	print $q->br() . "\n";
	print_ahref(gen_url(indexdir => ""), "Show list of archives");
	print $q->end_p();
	print $q->end_html();
	exit;

}

my $address_template = "<a href='" . gen_url(action => "search", -name => "<TMPL_VAR ESCAPE=URL NAME=NAMEURL>") . "'><TMPL_VAR ESCAPE=HTML NAME=NAME></a> <a href='" . gen_url(action => "search", -email => "<TMPL_VAR ESCAPE=URL NAME=EMAILURL>") . "'>&lt;<TMPL_VAR ESCAPE=HTML NAME=EMAIL>&gt;</a>";

my $subject_template = "<a href='" . gen_url(action => "tree", -id => "<TMPL_VAR ESCAPE=URL NAME=ID>") . "'><TMPL_VAR ESCAPE=HTML NAME=SUBJECT></a>";

my $download_template = "<b><a href='" . gen_url(action => "download", -id => "<TMPL_VAR ESCAPE=URL NAME=ID>", -path => "<TMPL_VAR NAME=PART>") . "'>Download</a></b>\n";

my $imagepreview_template = "<img src='" . gen_url(action => "download", -id => "<TMPL_VAR ESCAPE=URL NAME=ID>", -path => "<TMPL_VAR NAME=PART>") . "'>\n";

sub format_date($) {

	my ($date) = @_;
	$date = gmtime($date) if $date;
	# TODO: configure format
	$date = $date->strftime("%F %T %z") if $date;
	return $date if $date;
	return "";

}

sub parse_date($;$$) {

	my ($year, $month, $day) = @_;
	my $date1;
	my $date2;

	if ( defined $year and length $year and defined $month and length $month and defined $day and length $day ) {
		my $date;
		eval { $date = Time::Piece->strptime("$year $month $day", "%Y %m %d"); } or do { $date = undef; };
		if ( $date ) {
			$date1 = $date->epoch();
			$date2 = ($date + 24*60*60)->epoch();
		}
	} elsif ( defined $year and length $year and defined $month and length $month ) {
		my $date;
		eval { $date = Time::Piece->strptime("$year $month", "%Y %m"); } or do { $date = undef; };
		if ( $date ) {
			$date1 = $date->epoch();
			$date2 = $date->add_months(1)->epoch();
		}
	} elsif ( defined $year and length $year ) {
		my $date;
		eval { $date = Time::Piece->strptime("$year", "%Y"); } or do { $date = undef; };
		if ( $date ) {
			$date1 = $date->epoch();
			$date2 = $date->add_years(1)->epoch();
		}
	}

	return ($date1, $date2);

}

sub print_tree($$$$$$) {

	my ($index, $id, $desc, $rid, $limitup, $limitdown) = @_;

	my $count = 0;
	my %processed;

	my ($tree, $emails) = $index->db_tree($id, $desc, $rid, $limitup, $limitdown);
	if ( not $tree or not $tree->{root} ) {
		return 0;
	}
	my $root = ${$tree->{root}}[0];
	delete $tree->{root};

	$processed{$root} = 1;
	my @stack = ([$root, 0]);

	while ( @stack ) {

		my $m = pop(@stack);
		my ($tid, $len) = @{$m};
		my $down = $tree->{$tid};

		if ( $down ) {
			foreach ( reverse @{$down} ) {
				if ( not $processed{$_} ) {
					$processed{$_} = 1;
					push(@stack, [$_, $len+1]);
				}
			}
		}

		my $e = $emails->{$tid};

		my $mid = $e->{messageid};
		my $subject = $e->{subject};
		my $name = $e->{name};
		my $email = $e->{email};
		my $date = format_date($e->{date});

		$count++;

		print $q->start_Tr();

		print $q->start_td();
		for (my $i = 0; $i < $len; ++$i) { print "&emsp;" }
		print "&bull;&nbsp;";
		print_ahref(gen_url(action => "view", id => $mid), $subject, 1) if $subject;
		print $q->end_td();

		print $q->start_td();
		print_ahref(gen_url(action => "search", name => $name), $name, 1) if $name;
		print " " if $name and $email;
		print_ahref(gen_url(action => "search", email => $email), "<" . $email . ">", 1) if $email;
		print $q->end_td();

		print $q->start_td();
		print $q->escapeHTML($date) if $date;
		print $q->end_td();

		print $q->end_Tr() . "\n";

	}

	return $count;

}

if ( $action eq "get-bin" ) {

	error("Param id was not specified") unless $id;
	my $pemail = $index->email($id);
	error("Email with $id does not exist in archive $indexdir") unless $pemail;
	print $q->header(-type => "application/octet-stream", -attachment => "$id.bin", -charset => "");
	binmode(\*STDOUT, ":raw");
	PList::Email::Binary::to_fh($pemail, \*STDOUT);

} elsif ( $action eq "download" ) {

	error("Param id was not specified") unless $id;
	error("Param path was not specified") unless $path;

	my $part = $q->unescape($path);
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

	my $desc = $q->param("desc");

	error("Param id was not specified") unless $id;

	print_start_html("Tree for email $id");

	my $order = "";
	$order = 1 unless $desc;
	$order = $q->a({href => gen_url(id => $id, desc => $order)}, $order ? "(DESC)" : "(ASC)");

	print $q->start_table(-style => "white-space:nowrap") . "\n";
	print $q->Tr($q->th({-align => "left"}, ["Subject", "From", "Date $order"])) . "\n";

	my $count = print_tree($index, $id, $desc, undef, undef, undef);

	print $q->end_table() . "\n";

	print_p("(No emails)") unless $count;

	print $q->br() . "\n";
	print_ahref(gen_url(action => ""), "Show archive $indexdir");
	print_ahref(gen_url(indexdir => ""), "Show list of archives");
	print $q->end_html();

} elsif ( $action eq "view" ) {

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

	my $year = $id;
	(my $month, my $day, $_) = split("/", $path, 3);

	if ( not $year ) {
		print_start_html("Browse emails");
		print $q->start_p() . "\n";
		print_ahref(gen_url(action => "trees"), "Browse all");
		print $q->br() . "\n";
		print $q->b("Browse year:") . $q->br() . "\n";
		my $years = $index->db_date("%Y");
		if ( $years and @{$years} ) {
			print_ahref(gen_url(id => $_->[0]), $_->[0]) foreach @{$years};
		} else {
			print "(No years)" . $q->br() . "\n";
		}
	} elsif ( not $month ) {
		print_start_html("Browse emails for $year");
		print $q->start_p() . "\n";
		print_ahref(gen_url(action => "trees", id => $year), "Browse all in $year");
		print $q->br() . "\n";
		print $q->b("Browse month:") . $q->br() . "\n";
		my $months = $index->db_date("%m", "%Y", $year);
		if ( $months and @{$months} ) {
			print_ahref(gen_url(id => $year, path => $_->[0]), "$year-" . $_->[0]) foreach @{$months};
		} else {
			print "(No months)" . $q->br() . "\n";
		}
	} else {
		print_start_html("Browse emails for $year-$month");
		print $q->start_p() . "\n";
		print_ahref(gen_url(action => "trees", id => $year, path => $month), "Browse all in $year-$month");
		print $q->br() . "\n";
		print $q->b("Browse day:") . $q->br() . "\n";
		my $days = $index->db_date("%d", "%Y %m", "$year $month");
		if ( $days and @{$days} ) {
			print_ahref(gen_url(action => "trees", id => $year, path => $month . "/" . $_->[0]), "$year-$month-" . $_->[0]) foreach @{$days};
		} else {
			print "(No days)" . $q->br() . "\n";
		}
	}

	print $q->br() . "\n";
	print_ahref(gen_url(action => ""), "Show archive $indexdir");
	print_ahref(gen_url(indexdir => ""), "Show list of archives");
	print $q->end_p();
	print $q->end_html();

} elsif ( $action eq "roots" ) {

	my $year = $id;
	(my $month, my $day, $_) = split("/", $path, 3);
	(my $date1, my $date2) = parse_date($year, $month, $day);

	my $desc = $q->param("desc");
	my $limit = $q->param("limit");
	my $offset = $q->param("offset");

	$date1 = "" unless defined $date1;
	$date2 = "" unless defined $date2;
	$desc = "" unless defined $desc;
	$limit = 100 unless defined $limit and length $limit;
	$offset = 0 unless defined $offset and length $offset;

	$limit = "" if $limit == -1;

	my %args;
	$args{date1} = $date1 if length $date1;
	$args{date2} = $date2 if length $date2;
	$args{limit} = $limit+1 if length $limit;
	$args{offset} = $offset if length $offset;

	my $roots = $index->db_roots($desc, %args);
	error("Database error (db_roots)") unless $roots;

	my $order = "";
	$order = 1 unless $desc;
	$order = $q->a({href => gen_url(id => $id, path => $path, desc => $order, limit => $limit, offset => 0)}, $order ? "(DESC)" : "(ASC)");

	my $neednext = 0;
	my $nextoffset = $offset + scalar @{$roots};
	if ( length $limit and scalar @{$roots} > $limit ) {
		$nextoffset = $offset + $limit;
		$neednext = 1;
	}
	print_start_html("Roots of trees (" . ($offset + 1) . " \x{2013} " . $nextoffset . ")");

	print "View: ";
	print_ahref(gen_url(action => "trees", id => $id, path => $path), "Trees", 1);
	print " ";
	print_ahref(gen_url(action => "emails", id => $id, path => $path), "Emails", 1);
	print " Roots";
	print $q->br();
	print $q->br();

	print $q->start_table(-style => "white-space:nowrap") . "\n";
	print $q->Tr($q->th({-align => "left"}, ["Subject", "Date $order"])) . "\n";

	foreach ( @{$roots} ) {
		my $mid = $_->{messageid};
		my $subject = $_->{subject};
		my $date = format_date($_->{date});
		$subject = "unknown" unless $subject;
		print $q->start_Tr();
		print $q->start_td();
		print_ahref(gen_url(action => "tree", id => $mid), $subject, 1);
		print $q->end_td();
		print $q->start_td({style => "white-space:nowrap"});
		print $q->escapeHTML($date) if $date;
		print $q->end_td();
		print $q->end_Tr();
		print "\n";
	}

	print $q->end_table() . "\n";

	print_p("(No emails)") unless @{$roots};

	my $printbr = 1;
	if ( $neednext ) {
		$printbr = 0;
		print $q->br() . "\n";
		print_ahref(gen_url(id => $id, path => $path, desc => $desc, limit => $limit, offset => ($offset + $limit)), "Show next page");
	}

	if ( length $limit and $offset >= $limit ) {
		print $q->br() . "\n" if $printbr;
		print_ahref(gen_url(id => $id, path => $path, desc => $desc, limit => $limit, offset => ($offset - $limit)), "Show previous page");
	}

	print $q->br() . "\n";
	print_ahref(gen_url(action => ""), "Show archive $indexdir");
	print_ahref(gen_url(indexdir => ""), "Show list of archives");
	print $q->end_html();

} elsif ( $action eq "trees" ) {

	my $year = $id;
	(my $month, my $day, $_) = split("/", $path, 3);
	(my $date1, my $date2) = parse_date($year, $month, $day);

	my $limit = $q->param("limit");
	my $offset = $q->param("offset");
	my $desc = $q->param("desc");
	my $treedesc = $q->param("treedesc");

	$date1 = "" unless defined $date1;
	$date2 = "" unless defined $date2;
	$limit = 100 unless defined $limit and length $limit;
	$offset = 0 unless defined $offset and length $offset;
	$desc = "" unless defined $desc;
	$treedesc = "" unless defined $treedesc;

	$limit = "" if $limit == -1;

	my %args;
	$args{date1} = $date1 if length $date1;
	$args{date2} = $date2 if length $date2;
	$args{limit} = $limit+1 if length $limit;
	$args{offset} = $offset if $offset;

	my $roots = $index->db_roots($desc, %args);
	error("Database error (db_roots)") unless $roots;

	my $nextoffset;
	my $neednext = 0;
	my $count = 0;
	my $iter = 0;

	foreach ( @{$roots} ) {
		++$iter;
		if ( $neednext == 2 ) {
			$neednext = 1;
			last;
		}
		$count += $_->{count};
		$neednext = 2 if length $limit and $count >= $limit;
	}

	$neednext = 0 if $neednext != 1;
	$nextoffset = $offset + $iter if $neednext;

	print_start_html("Browse trees (" . ($offset + 1) . " \x{2013} " . $nextoffset . ")");

	print "View: Trees ";
	print_ahref(gen_url(action => "emails", id => $id, path => $path), "Emails", 1);
	print " ";
	print_ahref(gen_url(action => "roots", id => $id, path => $path), "Roots", 1);
	print $q->br();
	print $q->br();

	my $order = "";
	$order = 1 unless $desc;

	my $treeorder = "";
	$treeorder = 1 unless $treedesc;

	$order = $q->a({href => gen_url(id => $id, path => $path, limit => $limit, offset => 0, desc => $order, treedesc => $treedesc)}, $order ? "(thr DESC)" : "(thr ASC)");
	$treeorder = $q->a({href => gen_url(id => $id, path => $path, limit => $limit, offset => $offset, desc => $desc, treedesc => $treeorder)}, $treeorder ? "(msg DESC)" : "(msg ASC)");

	print $q->start_table(-style => "white-space:nowrap") . "\n";
	print $q->Tr($q->th({-align => "left"}, ["Subject", "From", "Date $order $treeorder"])) . "\n";

	$iter = -1;
	foreach ( @{$roots} ) {
		++$iter;
		last if $iter >= $nextoffset;
		print_tree($index, $_->{treeid}, $treedesc, 2, undef, undef);
	}

	print $q->end_table();

	if ( $neednext ) {
		print $q->br() . "\n";
		print_ahref(gen_url(id => $id, path => $path, limit => $limit, offset => $nextoffset, desc => $desc, treedesc => $treedesc), "Show next page");
	}

	print $q->br() . "\n";
	print_ahref(gen_url(action => ""), "Show archive $indexdir");
	print_ahref(gen_url(indexdir => ""), "Show list of archives");
	print $q->end_html();

} elsif ( $action eq "search" or $action eq "emails" ) {

	my $year = $id;
	(my $month, my $day, $_) = split("/", $path, 3);
	(my $date1, my $date2) = parse_date($year, $month, $day);

	my $str = $q->param("str");
	my $rid = $q->param("id");
	my $messageid = $q->param("messageid");
	my $treeid = $q->param("treeid");
	my $subject = $q->param("subject");
	my $email = $q->param("email");
	my $name = $q->param("name");
	my $type = $q->param("type");
	my $limit = $q->param("limit");
	my $offset = $q->param("offset");
	my $desc = $q->param("desc");
	my $submit = $q->param("submit");

	error("Param date1 is already specified in path") if defined $date1 and defined $q->param("date1");
	error("Param date2 is already specified in path") if defined $date2 and defined $q->param("date2");
	error("Bad action, should be search instead emails") if $action eq "emails" and ( defined $subject or defined $email or defined $name or defined $type );

	$date1 = $q->param("date1") unless defined $date1;
	$date2 = $q->param("date2") unless defined $date2;

	$str = "" unless defined $str;
	$rid = "" unless defined $rid;
	$messageid = "" unless defined $messageid;
	$treeid = "" unless defined $treeid;
	$subject = "" unless defined $subject;
	$email = "" unless defined $email;
	$name = "" unless defined $name;
	$type = "" unless defined $type;
	$date1 = "" unless defined $date1;
	$date2 = "" unless defined $date2;
	$limit = 100 unless defined $limit and length $limit;
	$offset = 0 unless defined $offset and length $offset;
	$desc = "" unless defined $desc;

	$limit = "" if $limit == -1;

	my %args;

	if ( not length $str ) {
		$args{id} = $rid if length $rid;
		$args{messageid} = $messageid if length $messageid;
		$args{treeid} = $treeid if length $treeid;
		$args{subject} = $subject if length $subject;
		$args{email} = $email if length $email;
		$args{name} = $name if length $name;
	}

	$args{type} = $type if length $type;
	$args{date1} = $date1 if length $date1;
	$args{date2} = $date2 if length $date2;

	$date1 = "" unless defined $q->param("date1");
	$date2 = "" unless defined $q->param("date2");

	if ( $action eq "search" and not $submit and not $str and not keys %args ) {
		# Show search form
		print_start_html("Search");
		print $q->start_form(-method => "GET", -action => gen_url(), -accept_charset => "utf-8");
		print $q->start_table() . "\n";
		print $q->Tr($q->td(["Subject:", $q->textfield(-name => "subject")])) . "\n";
		print $q->Tr($q->td(["Header type:", $q->popup_menu("type", ["", "from", "to", "cc"], "", {"" => "(any)"})])) . "\n";
		print $q->Tr($q->td(["Name:", $q->textfield(-name => "name")])) . "\n";
		print $q->Tr($q->td(["Email address:", $q->textfield(-name => "email")])) . "\n";
		# TODO: Add date1 and date2
		print $q->Tr($q->td(["Limit results:", $q->popup_menu("limit", ["10", "20", "50", "100", "200", "-1"], "100", {"-1" => "(unlimited)"})])) . "\n";
		print $q->Tr($q->td(["Sort order:", $q->popup_menu("desc", ["", "1"], "", {"" => "ascending", "1" => "descending"})])) . "\n";
		print $q->Tr($q->td($q->submit(-name => "submit", -value => "Search"))) . "\n";
		print $q->end_table() . "\n";
		print $q->end_form() . "\n";
		print $q->start_p() . "\n";
		print_ahref(gen_url(action => ""), "Show archive $indexdir");
		print_ahref(gen_url(indexdir => ""), "Show list of archives");
		print $q->end_p();
		print $q->end_html();
		exit;
	}

	$args{limit} = $limit+1 if length $limit;
	$args{offset} = $offset if $offset;
	$args{desc} = $desc if $desc;
	$args{implicit} = 0;

	my $emails;
	if ( length $str ) {
		$emails = $index->db_emails_str($str, %args);
	} else {
		$emails = $index->db_emails(%args);
	}

	error("Database error (db_emails)") unless $emails;

	my $order = "";
	$order = 1 unless $desc;
	$order = $q->a({href => gen_url(id => $id, path => $path, subject => $subject, email => $email, name => $name, type => $type, date1 => $date1, date2 => $date2, limit => $limit, offset => 0, desc => $order)}, $order ? "(DESC)" : "(ASC)");

	my $neednext = 0;
	my $nextoffset = $offset + scalar @{$emails};
	if ( length $limit and scalar @{$emails} > $limit ) {
		$nextoffset = $offset + $limit;
		$neednext = 1;
	}

	if ( $action eq "search" ) {
		print_start_html("Search (" . ($offset + 1) . " \x{2013} " . $nextoffset . ")");
	} else {
		print_start_html("Emails (" . ($offset + 1) . " \x{2013} " . $nextoffset . ")");
		print "View: ";
		print_ahref(gen_url(action => "trees", id => $id, path => $path), "Trees", 1);
		print " Emails ";
		print_ahref(gen_url(action => "roots", id => $id, path => $path), "Roots", 1);
		print $q->br();
		print $q->br();
	}
	print $q->start_table(-style => "white-space:nowrap") . "\n";
	print $q->Tr($q->th({-align => "left"}, ["Subject", "From", "Date $order"])) . "\n";

	foreach ( @{$emails} ) {
		my $mid = $_->{messageid};
		my $date = format_date($_->{date});
		my $subject = $_->{subject};
		my $email = $_->{email};
		my $name = $_->{name};
		$subject = "unknown" unless $subject;
		print $q->start_Tr();
		print $q->start_td();
		print_ahref(gen_url(action => "view", id => $mid), $subject, 1);
		print $q->end_td();
		print $q->start_td();
		print_ahref(gen_url(action => "search", name => $name), $name, 1) if $name;
		print " " if $name and $email;
		print_ahref(gen_url(action => "search", email => $email), "<" . $email . ">", 1) if $email;
		print $q->end_td();
		print $q->start_td({style => "white-space:nowrap"});
		print $q->escapeHTML($date) if $date;
		print $q->end_td();
		print $q->end_Tr();
		print "\n";
	}

	print $q->end_table() . "\n";

	print_p("(No emails)") unless @{$emails};

	my $printbr = 1;
	if ( $neednext ) {
		$printbr = 0;
		print $q->br() . "\n";
		print_ahref(gen_url(id => $id, path => $path, subject => $subject, email => $email, name => $name, type => $type, date1 => $date1, date2 => $date2, limit => $limit, offset => ($offset + $limit), desc => $desc), "Show next page");
	}

	if ( length $limit and $offset >= $limit ) {
		print $q->br() . "\n" if $printbr;
		print_ahref(gen_url(id => $id, path => $path, subject => $subject, email => $email, name => $name, type => $type, date1 => $date1, date2 => $date2, limit => $limit, offset => ($offset - $limit), desc => $desc), "Show previous page");
	}

	print $q->br() . "\n";
	print_ahref(gen_url(action => ""), "Show archive $indexdir");
	print_ahref(gen_url(indexdir => ""), "Show list of archives");
	print $q->end_html();

} else {

	error("Unknown value for param action");

}
