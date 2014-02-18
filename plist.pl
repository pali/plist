#!/usr/bin/perl

use strict;
use warnings;

use PList::Email;
use PList::Email::MIME;
use PList::Email::Binary;

use PList::Email::View;

use PList::List;
use PList::List::MBox;
use PList::List::Binary;

#use PList::Threads;
#use PList::Threads::Binary;

use PList::Index;

binmode STDOUT, ":utf8";

sub help() {

	print "help:\n";
#	print "index view <dir>\n";
#	print "index add-mbox <dir> [<mbox>]\n";
#	print "index add-mime <dir> [<mime>]\n";
#	print "index regenerate <dir>\n";
#	print "index del-mark <dir> <id>\n";
#	print "index del-unmark <dir> <id>\n";
#	print "index get-bin <dir> <id> [<bin>]\n";
#	print "index get-part <dir> <id> <part> [<file>]\n";
#	print "index gen-html <dir> <id> [<html>]\n";
#	print "index gen-txt <dir> <id> [<txt>]\n";
#	print "threads view <threads>\n";
#	print "threads add-list <threads> <list>\n";
#	print "threads add-id <threads> <id> <up> <list> <num>\n";
#	print "threads del-id <threads> <id>\n";
	print "index view <dir>\n";
	print "index create <dir> <database> <maxsize>\n";
	print "index add-list <dir> [<list>]\n";
	print "index add-mbox <dir> [<mbox>]\n";
	print "index add-mime <dir> [<mime>]\n";
	print "index get-bin <dir> <id> [<bin>]\n";
	print "index get-part <dir> <id> <part> [<file>]\n";
	print "index gen-html <dir> <id> [<html>]\n";
	print "index gen-txt <dir> <id> [<txt>]\n";
	print "index regenerate-database <dir>\n";
	print "index del-mark <dir> <id>\n";
	print "index del-unmark <dir> <id>\n";
	print "list view <list>\n";
	print "list add-mbox <list> [<mbox>]\n";
	print "list add-bin <list> [<bin>]\n";
	print "list get-bin <list> <offset> [<bin>]\n";
	print "list get-part <list> <offset> <part> [<file>]\n";
	print "list gen-html <list> <offset> [<html>]\n";
	print "list gen-txt <list> <offset> [<txt>]\n";
	print "bin view [<bin>]\n";
	print "bin from-mime [<mime>] [<bin>]\n";
	print "bin get-part <part> [<bin>] [<file>]\n";
	print "bin gen-html [<bin>] [<html>]\n";
	print "bin gen-txt [<bin>] [<txt>]\n";
	exit 1;

}

sub open_mbox($) {

	my ($filename) = @_;
	if ( not $filename ) {
		$filename = \*STDIN;
	}
	my $list = new PList::List::MBox($filename);
	die "Cannot open mbox file $filename\n" unless $list;
	return $list;

}

sub open_list($$$) {

	my ($filename, $readonly, $noheader) = @_;
	my $list = new PList::List::Binary($filename, $readonly, $noheader);
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

	my ($listfile, $binfile, $num) = @_;

	my $fh = open_output($binfile, ":raw");

	my $pemail = PList::List::Binary::read_from_list($listfile, $num);
	die "Cannot read email (num $num) from list file $listfile\n" unless $pemail;

	return ($pemail, $fh);

}


my $mod = shift @ARGV;
my $command = shift @ARGV;

if ( not $mod or not $command ) {

	help();

} elsif ( $mod eq "list" ) {

	my $listfile = shift @ARGV;
	help() unless $listfile;

	if ( $command eq "view" ) {

		my $list = open_list($listfile, 1, 0);

		my $count = $list->count();
		print "Total emails in list: $count\n\n";

		$count = 0;
		while ( not $list->eof() ) {
			my $pemail = $list->readnext();
			print "Number: $count\n";
			if (not $pemail) {
				print "Error: Corrupted email\n\n";
				++$count;
				next;
			}
			bin_view($pemail);
			print "\n";
			++$count;
		}

	} elsif ( $command eq "add-mbox" ) {

		my $mboxfile = shift @ARGV;

		my $mbox = open_mbox($mboxfile);
		my $list = open_list($listfile, 0, 1);

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

		$list->regenerate_header();

		print "Written $success (/$count) emails from mbox file $mboxfile to list file $listfile\n";

	} elsif ( $command eq "add-bin" ) {

		my $binfile = shift @ARGV;

		my $pemail = open_bin($binfile);
		my $list = open_list($listfile, 0, 0);

		$_ = $list->append($pemail);
		die "Cannot write email from bin file $binfile to list file $listfile\n" unless defined $_;

		print "Written one email from bin file $binfile to list file $listfile\n";

	} elsif ( $command eq "get-bin" ) {

		my $num = shift @ARGV;
		help() unless defined $num;

		my $file = shift @ARGV;

		my ($pemail, $fh) = bin_get($listfile, $file, $num);
		PList::Email::Binary::to_fh($pemail, $fh);

	} elsif ( $command eq "get-part" ) {

		my $num = shift @ARGV;
		help() unless defined $num;

		my $part = shift @ARGV;
		help() unless $part;

		my $file = shift @ARGV;

		my ($pemail, $fh) = bin_get($listfile, $file, $num);

		my $data = $pemail->data($part);
		die "Cannot read part $part from email (num $num) from list file $listfile\n" unless $data;

		print $fh $data;

	} elsif ( $command eq "gen-html" or $command eq "gen-txt" ) {

		my $num = shift @ARGV;
		help() unless defined $num;

		my $file = shift @ARGV;

		my ($pemail, $fh) = bin_get($listfile, $file, $num);

		binmode $fh, ":raw:utf8";

		my %args;
		$args{html_output} = 0 if ( $command eq "gen-txt" );

		my $output = PList::Email::View::to_str($pemail, %args);
		die "Cannot generate output\n" unless $output;

		print $fh $output;

	} else {

		help();

	}

} elsif ( $mod eq "bin" ) {

	if ( $command eq "view" ) {

		my $binfile = shift @ARGV;
		my $pemail = open_bin($binfile);
		bin_view($pemail);

	} elsif ( $command eq "from-mime" ) {

		my $mimefile = shift @ARGV;
		my $binfile = shift @ARGV;

		my $input = open_input($mimefile, ":raw");
		my $output = open_output($binfile, ":raw");

		my $str;

		{
			local $/=undef;
			$str = <$input>;
		}

		$str =~ s/^From .*\n//;

		my $pemail = PList::Email::MIME::from_str(\$str);
		die "Cannot read email\n" unless $pemail;

		$str = PList::Email::Binary::to_str($pemail);
		die "Cannot parse email\n" unless $str;

		print $output $str;

	} elsif ( $command eq "get-part" ) {

		my $part = shift @ARGV;
		help() unless $part;

		my $binfile = shift @ARGV;
		my $file = shift @ARGV;

		my $pemail = open_bin($binfile);
		my $output = open_output($file, ":raw");

		my $data = $pemail->data($part);
		die "Cannot read part $part from email bin file $binfile\n" unless $data;

		print $output ${$data};

	} elsif ( $command eq "gen-html" or $command eq "gen-txt" ) {

		my $binfile = shift @ARGV;
		my $file = shift @ARGV;

		my $pemail = open_bin($binfile);
		my $output = open_output($file, ":raw:utf8");

		my %args;
		$args{html_output} = 0 if ( $command eq "gen-txt" );

		my $str = PList::Email::View::to_str($pemail, %args);
		die "Cannot generate output\n" unless $str;

		print $output $str;

	} else {

		help();

	}

#} elsif ( $mod eq "threads" ) {
#
#	my $threadsfile = shift @ARGV;
#	help() unless $threadsfile;
#
#	my $threads = new PList::Threads::Binary($threadsfile);
#
#	if ( $command eq "view" ) {
#
#		print "Roots:";
#		print " " . $_ foreach(sort keys %{$threads->roots()});
#		print "\n";
#
#		foreach (sort keys %{$threads->emails()}) {
#			my $down = $threads->down($_) || [];
#			print "$_:";
#			print " (i)" if $threads->implicit($_);
#			print " " . $_ foreach(@{$down});
#			print "\n";
#		}
#
#	} elsif ( $command eq "add-list" ) {
#
#		# TODO
#
#	} elsif ( $command eq "add-id" ) {
#
#		my $id = shift @ARGV;
#		help() unless $id;
#
#		my $up = shift @ARGV;
#		help() unless $up;
#
#		my $list = shift @ARGV;
#		help() unless $list;
#
#		my $num = shift @ARGV;
#		help() unless $num;
#
#		die "Adding failed\n" unless $threads->add_email($id, $up, $list, $num);
#		die "Saving failed\n" unless $threads->save();
#
#		print "Done\n";
#
#	} elsif ( $command eq "del-id" ) {
#
#		my $id = shift @ARGV;
#		help() unless $id;
#
#		die "Deleting failed\n" unless $threads->del_email($id);
#		die "Saving failed\n" unless $threads->save();
#
#		print "Done\n";
#
#	} else {
#
#		help();
#
#	}
#
} elsif ( $mod eq "index" ) {

	my $indexdir = shift @ARGV;
	help() unless $indexdir;

	my $index = new PList::Index($indexdir);

	if ( $command eq "view" ) {

	} elsif ( $command eq "add-mbox" ) {

		my $mboxfile = shift @ARGV;
		my $mbox = open_mbox($mboxfile);

		my $count = $index->add_mbox($mbox);
		die "Adding mbox file $mboxfile to index dir $indexdir failed\n" unless $count;

		print "Added $count emails to index dir $indexdir";

	} elsif ( $command eq "add-mime" ) {

		my $mimefile = shift @ARGV;
		my $input = open_input($mimefile, ":raw");

		my $str;

		{
			local $/=undef;
			$str = <$input>;
		}

		$str =~ s/^From .*\n//;

		my $pemail = PList::Email::MIME::from_str(\$str);
		die "Cannot read email\n" unless $pemail;

		die "Adding email failed\n" unless $index->add_email($pemail);

	} elsif ( $command eq "regenerate" ) {

		print "Regenerating list files...\n";
		die "Failed\n" unless $index->regenerate_lists();

		print "Regeneraring threads files...\n";
		die "Failed\n" unless $index->regenreate_threads();

		print "Done\n";

	} elsif ( $command eq "del-mark" ) {

		my $id = shift @ARGV;
		help() unless $id;

		print "Marking email with $id as deleted (will not be visible)\n";
		die "Failed\n" unless $index->delete_mark($id);

		print "Done\n";

	} elsif ( $command eq "del-unmark" ) {

		my $id = shift @ARGV;
		help() unless $id;

		print "Unmarking email with $id as deleted (will be visible)\n";
		die "Failed\n" unless $index->delete_unmark($id);

		print "Done\n";

	} elsif ( $command eq "get-bin" or $command eq "gen-html" or $command eq "gen-txt" ) {

		my $id = shift @ARGV;
		help() unless $id;

		my $mode = ":raw:utf8";
		my %args;

		$args{html_output} = 0 if ( $command eq "gen-txt" );
		$mode = ":raw" if ( $command eq "get-bin" );

		my $binfile = shift @ARGV;
		my $fh = open_output($binfile, $mode);

		my $str;
		if ( $command eq "get-bin" ) {
			$str = $index->email($id);
		} else {
			$str = $index->view($id, %args);
		}
		die "Failed\n" unless $str;

		print $fh $str;

	} elsif ( $command eq "get-part" ) {

		my $id = shift @ARGV;
		help() unless $id;

		my $part = shift @ARGV;
		help() unless $part;

		my $file = shift @ARGV;
		my $fh = open_output($file, ":raw");

		my $str = $index->data($id, $part);
		die "Failed\n" unless $str;

		print $fh $str;

	} else {

		help();

	}

} else {

	help();

}
