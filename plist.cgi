#!/usr/bin/perl

use strict;
use warnings;

use FindBin qw($Bin);
use lib $Bin;

use PList::Index;
use PList::Email::Binary;
use PList::Template;

use CGI::Simple;
use Date::Format;
use Encode qw(decode_utf8 encode_utf8);
use Time::Piece;

binmode(\*STDOUT, ":utf8");

$CGI::Simple::PARAM_UTF8 = 1;

$ENV{HTML_TEMPLATE_ROOT} |= "$Bin/templates";

# global variables
my $q;
my $script;
my $indexdir;
my $action;
my $id;
my $path;

sub error($) {
	my ($msg) = @_;
	my $base_template = PList::Template->new("base.tmpl");
	my $errorpage_template = PList::Template->new("errorpage.tmpl");
	$errorpage_template->param(MSG => $msg);
	$base_template->param(TITLE => "Error 404");
	$base_template->param(BODY => $errorpage_template->output());
	print $q->header(-status => 404);
	print $base_template->output();
	exit;
}

sub escape($) {
	my ($str) = @_;
	return $q->url_encode(encode_utf8($str));
}

sub unescape($) {
	my ($str) = @_;
	return decode_utf8($q->url_decode($str));
}

sub gen_url {
	my $oldindexdir = escape($indexdir);
	my $oldaction = escape($action);
	my $oldid = escape($id);
	my $oldpath = escape($path);
	$oldpath =~ s/%2F/\//g;
	$oldpath =~ s/%5C/\\/g;
	my $newindexdir = $oldindexdir;
	my $newaction = $oldaction;
	my $newid = "";
	my $newpath = "";
	my $args = "?";
	my $fullurl;
	while ( @_ ) {
		my $key = shift;
		my $value = shift;
		if ( $key eq "fullurl" ) {
			$fullurl = $value;
		} elsif ( $key eq "indexdir" ) {
			$newindexdir = escape($value);
		} elsif ( $key eq "-indexdir" ) {
			$newindexdir = $value;
		} elsif ( $key eq "action" ) {
			$newaction = escape($value);
		} elsif ( $key eq "-action" ) {
			$newaction = $value;
		} elsif ( $key eq "id" ) {
			$newid = escape($value);
		} elsif ( $key eq "-id" ) {
			$newid = $value;
		} elsif ( $key eq "path" ) {
			$newpath = escape($value);
			$newpath =~ s/%2F/\//g;
			$newpath =~ s/%5C/\\/g;
		} elsif ( $key eq "-path" ) {
			$newpath = $value;
		} elsif ( $key =~ /^-(.*)$/ ) {
			$args .= $1 . "=" . $value . "&" if length $value;
		} else {
			$args .= escape($key) . "=" . escape($value) . "&" if length $value;
		}
	}
	chop($args);
	$newindexdir = "" unless $newindexdir;
	$newaction = "" unless $newaction and $newindexdir;
	$newid = "" unless $newid and $newaction;
	$newpath = "" unless $newpath and $newid;
	if ( not $fullurl and $newindexdir eq $oldindexdir and $newaction eq $oldaction and $newid eq $oldid and $newpath eq $oldpath ) {
		return "?" unless length($args);
		return $args;
	} else {
		$args = "/" . $args;
	}
	if ( not $fullurl and $newindexdir eq $oldindexdir and $newaction eq $oldaction and $newid eq $oldid and length($newpath) and not length($oldpath) ) {
		return $newpath . $args if length($args);
		return $newpath;
	} elsif ( not $fullurl and $newindexdir eq $oldindexdir and $newaction eq $oldaction and length($newid) and not length($oldid) ) {
		my $url = $newid;
		$url .= "/" . $newpath if length($newpath);
		$url .= $args if length($args);
		return $url;
	} elsif ( not $fullurl and $newindexdir eq $oldindexdir and length($newaction) and not length($oldaction) ) {
		my $url = $newaction;
		$url .= "/" . $newid if length($newid);
		$url .= "/" . $newpath if length($newpath);
		$url .= $args if length($args);
		return $url;
	} elsif ( not $fullurl and length($newindexdir) and not length($oldindexdir) ) {
		my $url = $newindexdir;
		$url .= "/" . $newaction if length($newaction);
		$url .= "/" . $newid if length($newid);
		$url .= "/" . $newpath if length($newpath);
		$url .= $args if length($args);
		return $url;
	} else {
		# TODO: use relative URL instead absolute $script
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
	my $uri = unescape($ENV{'REQUEST_URI'}); # request uri is escaped
	return "" unless $uri;
	$uri =~ s/\?.*$//s; # remove query string
	$uri =~ s/\+/ /g; # there is no difference between unescaped space and plus chars
	my $path_info = $q->path_info();
	$path_info =~ s/\+/ /g; # be consistent with uri
	$uri =~ s/\Q$path_info\E$//; # remove path_info
	return "" unless $uri;
	return $uri;
}

$q = CGI::Simple->new();
$q->charset("utf-8");

my $slash;

$script = get_script_url();
($slash, $indexdir, $action, $id, $path) = split(/(?<=\/)/, $q->path_info(), 5);

$slash = "" unless $slash;
$indexdir = "" unless $indexdir;
$action = "" unless $action and $indexdir;
$id = "" unless $id and $action;
$path = "" unless $path and $id;

# Check if each variable from uri ends with slash
if ( ( $slash ne "/" ) or ( length $indexdir and not $indexdir =~ /\/$/ ) or ( length $action and not $action =~ /\/$/ ) or ( length $id and not $id =~ /\/$/ ) ) {
	# Compose original url
	# NOTE: when .htaccess rewrite is in use and uri contains char '+' CGI.pm module not working correctly
	# Possible fix is to use path to script from get_script_url() function and compose original url from base and path_info
	my $url = $q->url(-base=>1) . $script . $q->path_info();
	if ( $url and not $url =~ /\/$/ ) {
		print $q->redirect($url . "/");
		exit 0;
	} else {
		error("Missing '/' at the end of URL");
	}
}

chop($indexdir) if $indexdir =~ /\/$/;
chop($action) if $action =~ /\/$/;
chop($id) if $id =~ /\/$/;
chop($path) if $path =~ /\/$/;

error("Invalid archive name $indexdir") if $indexdir =~ /[\\\/]/;

if ( not $indexdir ) {

	# List all directories in current directory

	my @dirs;

	my $dh;
	if ( not opendir($dh, ".") ) {
		error("Cannot open directory");
	}

	while ( defined (my $name = readdir($dh)) ) {
		next if $name =~ /^\./;
		next unless -d $name;
		next unless -f "$name/config";
		push(@dirs, $name);
	}

	closedir($dh);

	my @list;
	push(@list, {URL => gen_url(indexdir => $_), DIR => $_}) foreach sort { $a cmp $b } @dirs;

	my $base_template = PList::Template->new("base.tmpl");
	my $listpage_template = PList::Template->new("listpage.tmpl");

	$listpage_template->param(LIST => \@list);

	$base_template->param(TITLE => "List of archives");
	$base_template->param(BODY => $listpage_template->output());

	print $q->header();
	print $base_template->output();
	exit;

}

my $index = PList::Index->new($indexdir);
error("Archive $indexdir does not exist") unless $index;

my $templatedir = $index->info("templatedir");
if ( $templatedir and -e $templatedir ) {
	$ENV{HTML_TEMPLATE_ROOT} = $templatedir;
}

sub format_date($);

# Support for mhonarc urls
# /<year>/ => browse
# /<year>/<month>/ => trees
# /<year>/<month>/maillist.html => emails
# /<year>/<month>/subject.html => roots
# /<year>/<month>/threads.html => trees
# /<year>/<month>/author.html => ??? (sort by from field)
# /<year>/<month>/msg<XXXXX>.html => ??? (email with number XXXXX)
if ( $action =~ /^[0-9]+$/ ) {
	if ( not $id ) {
		print $q->redirect($q->url(-base=>1) . gen_url(action => "browse", id => $action, fullurl => 1));
		exit;
	} elsif ( $id =~ /^[0-9]+$/ ) {
		if ( not $path or $path eq "threads.html" ) {
			print $q->redirect($q->url(-base=>1) . gen_url(action => "trees", id => $action, path => $id, fullurl => 1));
			exit;
		} elsif ( $path eq "maillist.html" ) {
			print $q->redirect($q->url(-base=>1) . gen_url(action => "emails", id => $action, path => $id, fullurl => 1));
			exit;
		} elsif ( $path eq "subject.html" ) {
			print $q->redirect($q->url(-base=>1) . gen_url(action => "roots", id => $action, path => $id, fullurl => 1));
			exit;
		} elsif ( $path eq "author.html" ) { # TODO: Add support for sort by from field
			print $q->redirect($q->url(-base=>1) . gen_url(action => "emails", id => $action, path => $id, fullurl => 1));
			exit;
		} elsif ( $path =~ /^msg[0-9]{5}\.html$/ ) { # TODO: Add support for old emails links
			print $q->redirect($q->url(-base=>1) . gen_url(action => "", fullurl => 1));
			exit;
		}
	}
}

if ( not $action ) {

	# Show info page

	my $base_template = PList::Template->new("base.tmpl");
	my $infopage_template = PList::Template->new("infopage.tmpl");

	my @actions;
	push(@actions, {URL => gen_url(action => "browse"), ACTION => "Browse by year"});
	push(@actions, {URL => gen_url(action => "search"), ACTION => "Search emails"});
	push(@actions, {URL => gen_url(action => "trees"), ACTION => "Show all trees"});
	push(@actions, {URL => gen_url(action => "emails"), ACTION => "Show all emails"});
	push(@actions, {URL => gen_url(action => "roots"), ACTION => "Show all roots of emails"});

	my @emails;
	my $emails = $index->db_emails(limit => 10, implicit => 0, spam => 0, desc => 1);
	foreach ( @{$emails} ) {
		my $mid = $_->{messageid};
		my $date = format_date($_->{date});
		my $subject = $_->{subject};
		my $email = $_->{email};
		my $name = $_->{name};
		$subject = "unknown" unless $subject;
		push(@emails, {SUBJECT => $subject, URL => gen_url(action => "view", id => $mid), NAME => $name, SEARCHNAMEURL => gen_url(action => "search", type => "from", name => $name), EMAIL => $email, SEARCHEMAILURL => gen_url(action => "search", type => "from", email => $email), DATE => $date});

	}

	$infopage_template->param(DESCRIPTION => $index->info("description"));
	$infopage_template->param(EMAILS => \@emails);
	$infopage_template->param(ACTIONS => \@actions);
	$infopage_template->param(SEARCHURL => gen_url(action => "search"));

	$base_template->param(LISTURL => gen_url(indexdir => ""));
	$base_template->param(TITLE => "Archive $indexdir");
	$base_template->param(BODY => $infopage_template->output());

	print $q->header();
	print $base_template->output();
	exit;

}

sub format_date($) {

	my ($date) = @_;
	return "" unless $date;
	# TODO: configure format and timezone
	return time2str("%Y-%m-%d %T", $date);

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

sub gen_tree($$$$$$) {

	my ($index, $id, $desc, $rid, $limitup, $limitdown) = @_;

	my %processed;
	my @stack;

	my ($tree, $emails) = $index->db_tree($id, $desc, $rid, $limitup, $limitdown);
	if ( not $tree or not $tree->{root} ) {
		return;
	}
	my $root = ${$tree->{root}}[0];
	delete $tree->{root};

	%processed = ($root => 1);
	@stack = ([$root, 0]);

	my $depth = 1;

	while ( @stack ) {
		my $m = pop(@stack);
		my ($tid, $len) = @{$m};
		my $down = $tree->{$tid};

		if ( $depth < $len ) {
			$depth = $len;
		}

		if ( $down ) {
			foreach ( reverse @{$down} ) {
				if ( not $processed{$_} ) {
					$processed{$_} = 1;
					push(@stack, [$_, $len+1]);
				}
			}
		}
	}

	%processed = ($root => 1);
	@stack = ([$root, 0]);

	my @tree;

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
		my $implicit = $e->{implicit};
		my $date = format_date($e->{date});

		$subject = "unknown" if not $subject or $implicit;

		push(@tree, {WIDTH => sprintf("%.3f", $len * 70 / $depth), MAXWIDTH => $len * 16, SUBJECT => $subject, URL => $implicit ? undef : gen_url(action => "view", id => $mid), NAME => $name, SEARCHNAMEURL => gen_url(action => "search", type => "from", name => $name), EMAIL => $email, SEARCHEMAILURL => gen_url(action => "search", type => "from", email => $email), DATE => $date});

	}

	return \@tree;

}

if ( $action eq "get-bin" ) {

	error("Param id was not specified") unless $id;
	my $pemail = $index->email($id);
	error("Email with id $id does not exist in archive $indexdir") unless $pemail;
	print $q->header(-type => "application/octet-stream", -attachment => "$id.bin", -charset => "");
	binmode(\*STDOUT, ":raw");
	PList::Email::Binary::to_fh($pemail, \*STDOUT);

} elsif ( $action eq "download" ) {

	error("Param id was not specified") unless $id;
	error("Param path was not specified") unless $path;

	my $part = unescape($path);
	my $pemail = $index->email($id);
	error("Email with id $id does not exist in archive $indexdir") unless $pemail;
	error("Part $part of email with $id does not exist in archive $indexdir") unless $pemail->part($part);
	my $date = $pemail->header("0")->{date};
	my $size = $pemail->part($part)->{size};
	my $mimetype = $pemail->part($part)->{mimetype};
	my $filename = $pemail->part($part)->{filename};
	$date = time2str("%a, %d %b %Y %T GMT", $date, "GMT") if $date;
	$mimetype = "application/octet-stream" unless $mimetype;
	$filename = "File-$part.bin" unless $filename;
	$q->charset("") unless $mimetype =~ /^text\//;
	print $q->header(-type => $mimetype, -attachment => $filename, -expires => "+10y", last_modified => $date, -content_length => $size);
	binmode(\*STDOUT, ":raw");
	$pemail->data($part, \*STDOUT);

} elsif ( $action eq "tree" ) {

	my $desc = $q->param("desc");

	error("Param id was not specified") unless $id;

	my $order = "";
	$order = 1 unless $desc;

	my @trees = ({TREE => gen_tree($index, $id, $desc, undef, undef, undef)});

	my $base_template = PList::Template->new("base.tmpl");
	my $treepage_template = PList::Template->new("treepage.tmpl");

	$treepage_template->param(TREES => \@trees);
	$treepage_template->param(SORTSWITCH => "<a href=\"" . gen_url(id => $id, desc => $order) . "\">" . ( $order ? "(DESC)" : "(ASC)" ) . "</a>");

	$base_template->param(ARCHIVE => $indexdir);
	$base_template->param(ARCHIVEURL => gen_url(action => ""));
	$base_template->param(LISTURL => gen_url(indexdir => ""));
	$base_template->param(TITLE => "Archive $indexdir - Tree for email $id");
	$base_template->param(BODY => $treepage_template->output());

	print $q->header();
	print $base_template->output();

} elsif ( $action eq "view" ) {

	my $policy = $q->param("policy");
	my $monospace = $q->param("monospace");
	my $timezone = $q->param("timezone");
	my $dateformat = $q->param("dateformat");

	error("Param id was not specified") unless $id;

	my %config = (cgi_templates => 1);

	$config{html_policy} = $policy if defined $policy;
	$config{plain_monospace} = $monospace if defined $monospace;
	$config{time_zone} = $timezone if defined $timezone;
	$config{date_format} = $dateformat if defined $dateformat;

	my $str = $index->view($id, %config);
	error("Email with id $id does not exist in archive $indexdir") unless $str;

	my $size;
	{
		use bytes;
		$size = length(${$str});
	}

	print $q->header(-content_length => $size);
	print ${$str};

} elsif ( $action eq "browse" ) {

	my $year = $id;
	(my $month, my $ign, undef) = split("/", $path, 3);

	error("Odd param $ign") if $ign;

	my $body = "";

	my $base_template = PList::Template->new("base.tmpl");

	if ( not $year ) {

		$base_template->param(TITLE => "Archive $indexdir - Browse emails");

		my ($min, $max) = $index->db_stat();

		$body .= "Years:<br>\n";

		if ( $min and $max ) {
			$min = time2str("%Y", $min);
			$max = time2str("%Y", $max);
			foreach ($min..$max) {
				$body .= "<a href=\"" . gen_url(id => $_) . "\">$_ (" . $index->db_stat(parse_date($_)) . ")</a><br>\n";
			}
		} else {
			$body .= "(No emails)\n";
		}

	} elsif ( not $month ) {

		$base_template->param(TITLE => "Archive $indexdir - Browse emails for $year");

		$body .= "Months:<br>\n";

		for (1..12) {
			$body .= "<a href=\"" . gen_url(id => $year, path => $_) . "\">$year-$_ (" . $index->db_stat(parse_date($year, $_)) . ")</a><br>\n";
		}

	} else {

		$base_template->param(TITLE => "Archive $indexdir - Browse emails for $year-$month");

		$body .= "Days:<br>\n";

		my @days = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);

		my $max = $days[$month-1];

		if ( $month == 2 and ( (($year % 4 == 0) and ($year % 100 != 0)) or ($year % 400 == 0) ) ) {
			$max = 29;
		}

		for (1..$max) {
			$body .= "<a href=\"" . gen_url(action => "emails", id => $year, path => "$month/$_") . "\">$year-$month-$_ (" . $index->db_stat(parse_date($year, $month, $_)) . ")</a><br>\n";
		}

	}

	$base_template->param(BODY => $body);

	print $q->header();
	print $base_template->output();

} elsif ( $action eq "roots" ) {

	my $year = $id;
	(my $month, my $day, undef) = split("/", $path, 3);
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
	$order = "<a href=\"" . gen_url(id => $id, path => $path, desc => $order, limit => $limit, offset => 0) . "\">" . ( $order ? "(DESC)" : "(ASC)" ) . "</a>";

	my $neednext = 0;
	my $nextoffset = $offset + scalar @{$roots};
	if ( length $limit and scalar @{$roots} > $limit ) {
		$nextoffset = $offset + $limit;
		$neednext = 1;
	}

	my $title = "Archive $indexdir - Roots of trees";
	$title .= " (" . ($offset + 1) . " \x{2013} " . $nextoffset . ")" if $nextoffset > $offset;

	my @roots;

	foreach ( @{$roots} ) {
		my $mid = $_->{messageid};
		my $subject = $_->{subject};
		my $date = format_date($_->{date});
		$subject = "unknown" unless $subject;
		push(@roots, {SUBJECT => $subject, URL => gen_url(action => "tree", id => $mid), DATE => $date})
	}

	my $base_template = PList::Template->new("base.tmpl");
	my $rootspage_template = PList::Template->new("rootspage.tmpl");

	$rootspage_template->param(TREESURL => gen_url(action => "trees", id => $id, path => $path));
	$rootspage_template->param(EMAILSURL => gen_url(action => "emails", id => $id, path => $path));
	$rootspage_template->param(ROOTS => \@roots);
	$rootspage_template->param(SORTSWITCH => $order);

	$base_template->param(NEXTURL => gen_url(id => $id, path => $path, desc => $desc, limit => $limit, offset => ($offset + $limit))) if $neednext;
	$base_template->param(PREVURL => gen_url(id => $id, path => $path, desc => $desc, limit => $limit, offset => ($offset - $limit))) if length $limit and $offset >= $limit;
	$base_template->param(ARCHIVE => $indexdir);
	$base_template->param(ARCHIVEURL => gen_url(action => ""));
	$base_template->param(LISTURL => gen_url(indexdir => ""));
	$base_template->param(TITLE => $title);
	$base_template->param(BODY => $rootspage_template->output());

	print $q->header();
	print $base_template->output();

} elsif ( $action eq "trees" ) {

	my $year = $id;
	(my $month, my $day, undef) = split("/", $path, 3);
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

	my $title = "Archive $indexdir - Browse trees";
	$title .= " (" . ($offset + 1) . " \x{2013} " . $nextoffset . ")" if $nextoffset > $offset;

	my $order = "";
	$order = 1 unless $desc;

	my $treeorder = "";
	$treeorder = 1 unless $treedesc;

	$order = "<a href=\"" . gen_url(id => $id, path => $path, limit => $limit, offset => 0, desc => $order, treedesc => $treedesc) . "\">" . ( $order ? "(thr DESC)" : "(thr ASC)" ) . "</a>";
	$treeorder = "<a href=\"" . gen_url(id => $id, path => $path, limit => $limit, offset => $offset, desc => $desc, treedesc => $treeorder) . "\">" . ( $treeorder ? "(msg DESC)" : "(msg ASC)" ) . "</a>";

	my @trees;

	$iter = -1;
	foreach ( @{$roots} ) {
		++$iter;
		last if $iter >= $nextoffset;
		push(@trees, {TREE => gen_tree($index, $_->{treeid}, $treedesc, 2, undef, undef)});
	}

	my $base_template = PList::Template->new("base.tmpl");
	my $treespage_template = PList::Template->new("treespage.tmpl");

	$treespage_template->param(EMAILSURL => gen_url(action => "emails", id => $id, path => $path));
	$treespage_template->param(ROOTSURL => gen_url(action => "roots", id => $id, path => $path));
	$treespage_template->param(TREES => \@trees);
	$treespage_template->param(SORTSWITCH => $order . "<br>" . $treeorder);

	$base_template->param(NEXTURL => gen_url(id => $id, path => $path, limit => $limit, offset => $nextoffset, desc => $desc, treedesc => $treedesc)) if $neednext;
	$base_template->param(ARCHIVE => $indexdir);
	$base_template->param(ARCHIVEURL => gen_url(action => ""));
	$base_template->param(LISTURL => gen_url(indexdir => ""));
	$base_template->param(TITLE => $title);
	$base_template->param(BODY => $treespage_template->output());

	print $q->header();
	print $base_template->output();

} elsif ( $action eq "search" or $action eq "emails" ) {

	my $year = $id;
	(my $month, my $day, undef) = split("/", $path, 3);
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

		my $base_template = PList::Template->new("base.tmpl");
		my $searchpage_template = PList::Template->new("searchpage.tmpl");

		$searchpage_template->param(SEARCHURL => gen_url());

		$base_template->param(ARCHIVE => $indexdir);
		$base_template->param(ARCHIVEURL => gen_url(action => ""));
		$base_template->param(LISTURL => gen_url(indexdir => ""));
		$base_template->param(TITLE => "Archive $indexdir - Search");
		$base_template->param(BODY => $searchpage_template->output());

		print $q->header();
		print $base_template->output();
		exit;

	}

	$args{limit} = $limit+1 if length $limit;
	$args{offset} = $offset if $offset;
	$args{desc} = $desc if $desc;
	$args{implicit} = 0;
	$args{spam} = 0;

	my $emails;
	if ( length $str ) {
		$emails = $index->db_emails_str($str, %args);
	} else {
		$emails = $index->db_emails(%args);
	}

	error("Database error (db_emails)") unless $emails;

	my $order = "";
	$order = 1 unless $desc;
	$order = "<a href=\"" . gen_url(id => $id, path => $path, str => $str, messageid => $messageid, treeid => $treeid, subject => $subject, email => $email, name => $name, type => $type, date1 => $date1, date2 => $date2, limit => $limit, offset => 0, desc => $order) . "\">" . ( $order ? "(DESC)" : "(ASC)" ) . "</a>";

	my $neednext = 0;
	my $nextoffset = $offset + scalar @{$emails};
	if ( length $limit and scalar @{$emails} > $limit ) {
		$nextoffset = $offset + $limit;
		$neednext = 1;
	}

	my $title = "Archive $indexdir -";
	$title .= " Quick Search for $str" if $action eq "search" and length $str;
	$title .= " Search" if $action eq "search";
	$title .= " Emails" if $action eq "emails";
	$title .= " (" . ($offset + 1) . " \x{2013} " . $nextoffset . ")" if $nextoffset > $offset;

	my $base_template = PList::Template->new("base.tmpl");
	my $page_template;

	if ( $action eq "search" and not length $str ) {
		$page_template = PList::Template->new("searchrespage.tmpl");
		$page_template->param(SUBJECT => $subject) if length $subject;
		$page_template->param(TYPE => $subject) if length $type;
		$page_template->param(NAME => $name) if length $name;
		$page_template->param(EMAIL => $email) if length $email;
	}

	if ( $action eq "emails" ) {
		$page_template = PList::Template->new("emailspage.tmpl");
		$page_template->param(TREESURL => gen_url(action => "trees", id => $id, path => $path));
		$page_template->param(ROOTSURL => gen_url(action => "roots", id => $id, path => $path));
	}

	my @emails;
	foreach ( @{$emails} ) {
		my $mid = $_->{messageid};
		my $date = format_date($_->{date});
		my $subject = $_->{subject};
		my $email = $_->{email};
		my $name = $_->{name};
		$subject = "unknown" unless $subject;
		push(@emails, {SUBJECT => $subject, URL => gen_url(action => "view", id => $mid), NAME => $name, SEARCHNAMEURL => gen_url(action => "search", type => "from", name => $name), EMAIL => $email, SEARCHEMAILURL => gen_url(action => "search", type => "from", email => $email), DATE => $date});
	}

	$page_template->param(SORTSWITCH => $order);
	$page_template->param(EMAILS => \@emails);

	$base_template->param(NEXTURL => gen_url(id => $id, path => $path, str => $str, messageid => $messageid, treeid => $treeid, subject => $subject, email => $email, name => $name, type => $type, date1 => $date1, date2 => $date2, limit => $limit, offset => ($offset + $limit), desc => $desc)) if $neednext;
	$base_template->param(PREVURL => gen_url(id => $id, path => $path, str => $str, messageid => $messageid, treeid => $treeid, subject => $subject, email => $email, name => $name, type => $type, date1 => $date1, date2 => $date2, limit => $limit, offset => ($offset - $limit), desc => $desc)) if length $limit and $offset >= $limit;
	$base_template->param(ARCHIVE => $indexdir);
	$base_template->param(ARCHIVEURL => gen_url(action => ""));
	$base_template->param(LISTURL => gen_url(indexdir => ""));
	$base_template->param(TITLE => $title);
	$base_template->param(BODY => $page_template->output());

	print $q->header();
	print $base_template->output();

} else {

	error("Unknown value for param action");

}
