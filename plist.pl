#!/usr/bin/perl

use strict;
use warnings;

use FindBin qw($Bin);
use lib $Bin;

use PList::Email;
use PList::Email::MIME;
use PList::Email::Binary;

use PList::Email::View;

use PList::List;
use PList::List::MBox;
use PList::List::Binary;

use PList::Index;

binmode STDOUT, ":utf8";

$ENV{HTML_TEMPLATE_ROOT} |= "$Bin/templates";

sub help() {

	print "help:\n";
	print "index view <dir>\n";
	print "index create <dir> [<driver>] [<params>] [<username>] [<password>]\n";
#	print "index regenerate <dir>\n";
	print "index add-list <dir> [<list>] [silent]\n";
	print "index add-mbox <dir> [<mbox>] [silent]\n";
	print "index add-mail <dir> [<mail>]\n";
	print "index get-bin <dir> <id> [<bin>]\n";
	print "index get-part <dir> <id> <part> [<file>]\n";
	print "index get-roots <dir> [desc] [date1] [date2] [limit] [offset]\n";
	print "index get-tree <dir> <id> [<file>]\n";
	print "index gen-html <dir> <id> [<html>]\n";
#	print "index gen-txt <dir> <id> [<txt>]\n";
	print "index del <dir> <id>\n";
	print "index setspam <dir> <id> <true|false>\n";
	print "index pregen <dir> [<id>]\n";
	print "list view <list>\n";
	print "list add-mbox <list> [<mbox>]\n";
	print "list add-bin <list> [<bin>]\n";
	print "list get-bin <list> <offset> [<bin>]\n";
	print "list get-part <list> <offset> <part> [<file>]\n";
	print "list gen-html <list> <offset> [<html>]\n";
#	print "list gen-txt <list> <offset> [<txt>]\n";
	print "bin view [<bin>]\n";
	print "bin from-mail [<mail>] [<bin>]\n";
	print "bin get-part <part> [<bin>] [<file>]\n";
	print "bin gen-html [<bin>] [<html>]\n";
#	print "bin gen-txt [<bin>] [<txt>]\n";
	exit 1;

}

sub open_mbox($) {

	my ($filename) = @_;
	if ( not $filename ) {
		$filename = \*STDIN;
	}
	my $list = PList::List::MBox->new($filename);
	die "Cannot open mbox file $filename\n" unless $list;
	return $list;

}

sub open_list($$) {

	my ($filename, $append) = @_;
	my $list = PList::List::Binary->new($filename, $append);
	die "Cannot open list file $filename\n" unless $list;
	return $list;

}

sub open_bin($) {

	my ($filename) = @_;
	my $pemail;
	if ( $filename ) {
		$pemail = PList::Email::Binary::from_file($filename);
	} else {
		$pemail = PList::Email::Binary::from_fh(\*STDIN);
	}
	die "Cannot open bin file $filename\n" unless $pemail;
	return $pemail;

}

sub open_input($$) {

	my ($filename, $mode) = @_;
	my $fh;
	if ( $filename ) {
		if ( not open($fh, "<:mmap" . $mode, $filename) ) {
			die "Cannot open input file $filename\n";
		}
	} else {
		$fh = \*STDIN;
		binmode $fh, $mode;
	}
	return $fh;

}

sub open_output($$) {

	my ($filename, $mode) = @_;
	my $fh;
	if ( $filename ) {
		if ( not open($fh, ">" . $mode, $filename) ) {
			die "Cannot open output file $filename\n";
		}
	} else {
		$fh = \*STDOUT;
		binmode $fh, $mode;
	}
	return $fh;

}

sub bin_view($) {

	my ($pemail) = @_;

	my $header = $pemail->header("0");
	if ( not $header ) {
		print "Error: Corrupted header\n";
		return;
	}

	print "Id: " .$header->{id} . "\n";

	if ( $header->{from} and @{$header->{from}} ) {
		print "From:";
		foreach (@{$header->{from}}) {
			$_ =~ /^(\S*)/;
			print " " . $1;
		}
		print "\n";
	}

	if ( $header->{to} and @{$header->{to}} ) {
		print "To:";
		foreach (@{$header->{to}}) {
			$_ =~ /^(\S*)/;
			print " " . $1;
		}
		print "\n";
	}

	if ( $header->{cc} and @{$header->{cc}} ) {
		print "Cc:";
		foreach (@{$header->{cc}}) {
			$_ =~ /^(\S*)/;
			print " " . $1;
		}
		print "\n";
	}

	if ( $header->{subject} ) {
		print "Subject: " . $header->{subject} . "\n";
	}

	print "Parts:";
	print " " . $_ foreach sort keys %{$pemail->parts()};
	print "\n";

}

sub bin_get($$$) {

	my ($listfile, $binfile, $offset) = @_;

	my $fh = open_output($binfile, ":raw");
	my $list = open_list($listfile, 0);
	my $pemail = $list->readat($offset);
	die "Cannot read email (at $offset) from list file $listfile\n" unless $pemail;

	return ($pemail, $fh);

}

sub index_tree_get($$$) {

	my ($index, $messageid, $fh) = @_;

	my ($tree, $emails) = $index->db_tree($messageid, 0, 0);
	if ( not $tree or not $tree->{root} ) {
		($tree, $emails) = $index->db_tree($messageid, 0, 2);
	}
	if ( not $tree or not $tree->{root} ) {
		print "Error: Tree not found\n";
		return;
	}

	my $email;
	foreach ( keys %{$emails} ) {
		next if $emails->{$_}->{messageid} ne $messageid;
		$email = $emails->{$_};
	}

	if ( $email ) {

		my $id = $email->{id};
		my $implicit = $email->{implicit};
		my $date = $email->{date};
		my $subject = $email->{subject};
		my $from = $email->{name} . " <" . $email->{email} . ">";

		print $fh "Internal id: $id\n";
		print $fh "Id: $messageid\n";
		print $fh "From: $from\n";

		if ( $date ) {
			print $fh "Date: $date\n";
		}

		if ( $subject ) {
			print $fh "Subject: $subject\n";
		}

	}

	my $root = ${$tree->{root}}[0];

	delete $tree->{root};

	my @keys = sort { $a <=> $b } keys %{$tree};
	my $len = length(pop(@keys))+1;
	my $space = " " x $len;

	my %processed = ( $root => 1 );
	my @stack = ($root);
	my @len = ();
	my $linelen = 0;

	print $fh "Tree:\n";

	while (@stack) {

		my $tid = pop(@stack);

		my $size = scalar @stack;

		my $down = $tree->{$tid};

		if ( $down ) {
			foreach ( reverse @{$down} ) {
				if ( not $processed{$_} ) {
					$processed{$_} = 1;
					push(@stack, $_);
					push(@len, $linelen+1);
				}
			}
		}

		printf $fh " %" . ($len-1) . "d", $tid;

		$linelen = pop(@len) if @stack;

		if ( $size == scalar @stack ) {
			print $fh "\n";
			print $fh $space x $linelen if @stack;
		}

	}

}


my $mod = shift @ARGV;
my $command = shift @ARGV;

if ( not $mod or not $command ) {

	help();

} elsif ( $mod eq "list" ) {

	my $listfile = shift @ARGV;
	help() unless $listfile;

	if ( $command eq "view" ) {

		help() if @ARGV;

		my $list = open_list($listfile, 0);

		my $count = 0;
		while ( not $list->eof() ) {
			my $offset = $list->offset();
			my $pemail = $list->readnext();
			print "\n" if $count != 0;
			if (not $pemail) {
				print "Error: Corrupted email\n\n";
				++$count;
				next;
			}
			print "Offset: $offset\n";
			bin_view($pemail);
			++$count;
		}

		print "\n" if $count != 0;
		print "Total emails: $count\n";

	} elsif ( $command eq "add-mbox" ) {

		my $mboxfile = shift @ARGV;

		help() if @ARGV;

		my $mbox = open_mbox($mboxfile);
		my $list = open_list($listfile, 1);

		$mboxfile = "STDIN" unless $mboxfile;

		my $count = 0;
		my $success = 0;

		while ( not $mbox->eof() ) {

			++$count;

			my $pemail = $mbox->readnext();
			if ( not $pemail ) {
				warn "Cannot read email from mbox file $mboxfile ($count)\n";
				next;
			}

			if ( not defined $list->append($pemail) ) {
				warn "Cannot write email to list file $listfile ($count)\n";
				next;
			}

			++$success;

		}

		print "Written $success (/$count) emails from mbox file $mboxfile to list file $listfile\n";

	} elsif ( $command eq "add-bin" ) {

		my $binfile = shift @ARGV;

		help() if @ARGV;

		my $pemail = open_bin($binfile);
		my $list = open_list($listfile, 1);

		$binfile = "STDIN" unless $binfile;

		my $ret = $list->append($pemail);
		die "Cannot write email from bin file $binfile to list file $listfile\n" unless defined $ret;

		print "Written one email from bin file $binfile to list file $listfile\n";

	} elsif ( $command eq "get-bin" ) {

		my $offset = shift @ARGV;
		help() unless defined $offset;

		my $file = shift @ARGV;

		help() if @ARGV;

		my ($pemail, $fh) = bin_get($listfile, $file, $offset);
		PList::Email::Binary::to_fh($pemail, $fh);

	} elsif ( $command eq "get-part" ) {

		my $offset = shift @ARGV;
		help() unless defined $offset;

		my $part = shift @ARGV;
		help() unless $part;

		my $file = shift @ARGV;

		help() if @ARGV;

		my ($pemail, $fh) = bin_get($listfile, $file, $offset);

		my $ret = $pemail->data($part, $fh);
		die "Cannot read part $part from email (at $offset) from list file $listfile\n" unless $ret;

	} elsif ( $command eq "gen-html" or $command eq "gen-txt" ) {

		my $offset = shift @ARGV;
		help() unless defined $offset;

		my $file = shift @ARGV;

		help() if @ARGV;

		my ($pemail, $fh) = bin_get($listfile, $file, $offset);

		binmode $fh, ":raw:utf8";

		my %args;
		$args{html_output} = 0 if ( $command eq "gen-txt" );

		my $output = PList::Email::View::to_str($pemail, %args);
		die "Cannot generate output\n" unless $output;

		print $fh ${$output};

	} else {

		help();

	}

} elsif ( $mod eq "bin" ) {

	if ( $command eq "view" ) {

		my $binfile = shift @ARGV;
		help() if @ARGV;
		my $pemail = open_bin($binfile);
		bin_view($pemail);

	} elsif ( $command eq "from-mail" ) {

		my $mailfile = shift @ARGV;
		my $binfile = shift @ARGV;
		help() if @ARGV;

		my $input = open_input($mailfile, ":raw");
		my $output = open_output($binfile, ":raw");

		my $str;
		my $len;

		{
			local $/=undef;
			$str = <$input>;
		}

		my $pemail = PList::Email::MIME::from_str(\$str);
		die "Cannot read email\n" unless $pemail;

		($str, $len) = PList::Email::Binary::to_str($pemail);
		die "Cannot parse email\n" unless $str;

		print $output ${$str};

	} elsif ( $command eq "get-part" ) {

		my $part = shift @ARGV;
		help() unless $part;

		my $binfile = shift @ARGV;
		my $file = shift @ARGV;

		help() if @ARGV;

		my $pemail = open_bin($binfile);
		my $output = open_output($file, ":raw");

		my $ret = $pemail->data($part, $output);
		die "Cannot read part $part from email bin file $binfile\n" unless $ret;

	} elsif ( $command eq "gen-html" or $command eq "gen-txt" ) {

		my $binfile = shift @ARGV;
		my $file = shift @ARGV;
		help() if @ARGV;

		my $pemail = open_bin($binfile);
		my $output = open_output($file, ":raw:utf8");

		my %args;
		$args{html_output} = 0 if ( $command eq "gen-txt" );

		my $str = PList::Email::View::to_str($pemail, %args);
		die "Cannot generate output\n" unless $str;

		print $output ${$str};

	} else {

		help();

	}

} elsif ( $mod eq "index" ) {

	my $indexdir = shift @ARGV;
	help() unless $indexdir;

	if ( $command eq "create" ) {

		my $driver = shift @ARGV;
		my $params = shift @ARGV;
		my $username = shift @ARGV;
		my $password = shift @ARGV;

		help() if @ARGV;

		print "Creating index dir '$indexdir'...\n";
		die "Failed\n" unless PList::Index::create($indexdir, $driver, $params, $username, $password);
		print "Done\n";

		exit 0;

	}

	my $index = PList::Index->new($indexdir);
	die "Cannot open index dir '$indexdir'\n" unless $index;

	if ( $command eq "view" ) {

		help() if @ARGV;

		print "Directory: $indexdir\n";
		print "Description: " . $index->info("description") . "\n";
		print "SQL driver: " . $index->info("driver") . "\n";
		print "Average size of list file: " . $index->info("listsize") . " bytes\n";
		print "Number of email trees: " . $index->info("treecount") . "\n";
		print "Number of emails: " . $index->info("emailcount") . "\n";

		my $email = $index->info("emaillast");
		if ( not $email ) {
			print "Last email: (unknown)\n";
		} else {
			print "Last email:";
			print " from: \"" . $email->{name} . "\" <" . $email->{email} . ">";
			print " with subject: \"" . $email->{subject} . "\"\n";
		}

	} elsif ( $command eq "regenerate" ) {

		help() if @ARGV;
		print "Regenerating index dir '$indexdir'...\n";
		die "Failed\n" unless $index->regenerate();
		print "Done\n"

	} elsif ( $command eq "add-list" ) {

		my $listfile = shift @ARGV;
		my $silent = shift @ARGV;
		help() if @ARGV;
		my $list = open_list($listfile, 0);
		$listfile = "STDIN" unless $listfile;

		print "Adding list file '$listfile' to index dir '$indexdir'...\n";
		my ($count, $total) = $index->add_list($list, $silent);
		print "Done ($count/$total emails)\n";

	} elsif ( $command eq "add-mbox" ) {

		my $mboxfile = shift @ARGV;
		my $silent = shift @ARGV;
		help() if @ARGV;
		my $mbox = open_mbox($mboxfile);
		$mboxfile = "STDIN" unless $mboxfile;

		print "Adding mbox file '$mboxfile' to index dir '$indexdir'...\n";
		my ($count, $total) = $index->add_list($mbox, $silent);
		print "Done ($count/$total emails)\n";

	} elsif ( $command eq "add-mail" ) {

		my $mailfile = shift @ARGV;
		help() if @ARGV;
		my $input = open_input($mailfile, ":raw");
		$mailfile = "STDIN" unless $mailfile;

		my $str;

		{
			local $/=undef;
			$str = <$input>;
		}

		print "Adding MIME email file '$mailfile' to index dir '$indexdir'...\n";
		my $pemail = PList::Email::MIME::from_str(\$str);
		die "Failed (Cannot read email)\n" unless $pemail;

		die "Failed (Cannot add email)\n" unless $index->add_email($pemail);
		print "Done\n";

	} elsif ( $command eq "get-roots" ) {

		my $desc = shift @ARGV;
		my $date1 = shift @ARGV;
		my $date2 = shift @ARGV;
		my $limit = shift @ARGV;
		my $offset = shift @ARGV;
		help() if @ARGV;

		my %args;
		$args{date1} = $date1 if defined $date1;
		$args{date2} = $date2 if defined $date2 and $date2 != -1;
		$args{limit} = $limit if defined $limit;
		$args{offset} = $offset if defined $offset;

		my $roots = $index->db_roots($desc, %args);

		print "Roots:\n";
		printf("%7s %12s %7s\n", "treeid", "date", "subject");
		if ( $roots ) {
			foreach ( @{$roots} ) {
				if ( $_ ) {
					printf("%7d %12d %7s\n", $_->{treeid}, $_->{date}, $_->{subject});
				}
			}
		}

	} elsif ( $command eq "get-bin" or $command eq "get-tree" or $command eq "gen-html" or $command eq "gen-txt" ) {

		my $id = shift @ARGV;
		help() unless $id;

		my $mode = ":raw:utf8";
		my %args;

		$args{html_output} = 0 if ( $command eq "gen-txt" );
		$mode = ":raw" if ( $command eq "get-bin" );

		my $outputfile = shift @ARGV;
		help() if @ARGV;
		my $fh = open_output($outputfile, $mode);

		if ( $command eq "get-bin" ) {
			my $pemail = $index->email($id);
			die "Failed\n" unless $pemail;
			PList::Email::Binary::to_fh($pemail, $fh);
		} elsif ( $command eq "get-tree" ) {
			index_tree_get($index, $id, $fh);
			exit 0;
		} else {
			my $str = $index->view($id, %args);
			die "Failed\n" unless $str;
			print $fh ${$str};
		}

	} elsif ( $command eq "get-part" ) {

		my $id = shift @ARGV;
		help() unless $id;

		my $part = shift @ARGV;
		help() unless $part;

		my $file = shift @ARGV;
		help() if @ARGV;
		my $fh = open_output($file, ":raw");

		my $ret = $index->data($id, $part, $fh);
		die "Failed\n" unless $ret;

	} elsif ( $command eq "del" ) {

		my $id = shift @ARGV;
		help() unless $id;
		help() if @ARGV;

		print "Deleting email with $id...\n";
		die "Failed\n" unless $index->delete($id);

		print "Done\n";

	} elsif ( $command eq "setspam" ) {

		my $id = shift @ARGV;
		help() unless $id;
		my $val = shift @ARGV;
		help() unless $val;
		help() if @ARGV;

		if ( $val eq "false" ) {
			$val = 0;
		} elsif ( $val eq "true" ) {
			$val = 1;
		} else {
			help();
		}

		print "Marking email with $id as " . ( $val ? "" : "not " ) . "spam...\n";
		die "Failed\n" unless $index->setspam($id, $val);

		print "Done\n";

	} elsif ( $command eq "pregen" ) {

		my $id = shift @ARGV;
		help() if @ARGV;

		if ( $id ) {
			print "Pregenerating email with $id...\n";
			die "Failed\n" unless $index->pregen_one_email($id);
			print "Done\n";
		} else {
			print "Pregenerating all emails...\n";
			my ($count, $total) = $index->pregen_all_emails();
			print "Done ($count/$total emails)\n";
		}

	} else {

		help();

	}

} else {

	help();

}
