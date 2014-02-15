package PList::Email::View;

use strict;
use warnings;

use Encode qw(decode_utf8);

use PList::Email;

use HTML::FromText;
use HTML::Template;

BEGIN {
	# Package Number::Bytes::Human is sometimes not available
	# Than do not fail but simply return original number
	eval {
		require Number::Bytes::Human;
		import Number::Bytes::Human qw(format_bytes);
	} or do {
		sub format_bytes { return "@_"; }
	}
}

my $t2h = HTML::FromText->new();

my @disabled_mime_types_default = qw(application/pgp-signature);

my $base_template_default = <<END;
<html>
<head>
<meta http-equiv='Content-Type' content='text/html; charset=UTF-8'>
<TMPL_IF NAME=TITLE><title><TMPL_VAR ESCAPE=HTML NAME=TITLE></title>
</TMPL_IF></head>
<body>
<TMPL_IF NAME=BODY><TMPL_VAR NAME=BODY>
</TMPL_IF></body>
</html>
END

my $message_template_default = <<END;
<TMPL_IF NAME=FROM><b>From:</b><TMPL_LOOP NAME=FROM> <a href='mailto:<TMPL_VAR ESCAPE=URL NAME=EMAIL>'><TMPL_VAR ESCAPE=HTML NAME=NAME> &lt;<TMPL_VAR ESCAPE=HTML NAME=EMAIL>&gt;</a></TMPL_LOOP><br>
</TMPL_IF><TMPL_IF NAME=TO><b>To:</b><TMPL_LOOP NAME=TO> <a href='mailto:<TMPL_VAR ESCAPE=URL NAME=EMAIL>'><TMPL_VAR ESCAPE=HTML NAME=NAME> &lt;<TMPL_VAR ESCAPE=HTML NAME=EMAIL>&gt;</a></TMPL_LOOP><br>
</TMPL_IF><TMPL_IF NAME=CC><b>Cc:</b><TMPL_LOOP NAME=CC> <a href='mailto:<TMPL_VAR ESCAPE=URL NAME=EMAIL>'><TMPL_VAR ESCAPE=HTML NAME=NAME> &lt;<TMPL_VAR ESCAPE=HTML NAME=EMAIL>&gt;</a></TMPL_LOOP><br>
</TMPL_IF><TMPL_IF NAME=DATE><b>Date:</b> <TMPL_VAR ESCAPE=HTML NAME=DATE><br>
</TMPL_IF><TMPL_IF NAME=SUBJECT><b>Subject:</b> <TMPL_VAR ESCAPE=HTML NAME=SUBJECT>
</TMPL_IF>
END

my $view_template_default = <<END;
<TMPL_IF NAME=BODY><div style='margin:5px; padding:5px; border:1px solid'>
<TMPL_VAR NAME=BODY></div></TMPL_IF>
END

my $plaintext_template_default = <<END;
<TMPL_IF NAME=BODY><span style='white-space:pre-wrap; font-family:monospace'><TMPL_VAR ESCAPE=HTML NAME=BODY></span></TMPL_IF>
END

my $multipart_template_default = <<END;
<TMPL_IF NAME=BODY><TMPL_LOOP NAME=BODY><TMPL_VAR NAME=PART></TMPL_LOOP></TMPL_IF>
END

my $attachment_template_default = <<END;
<b>Filename:</b> <TMPL_VAR ESCAPE=HTML NAME=FILENAME>
<TMPL_IF NAME=DESCRIPTION><br><b>Description:</b> <TMPL_VAR ESCAPE=HTML NAME=DESCRIPTION>
</TMPL_IF><br><b>Mimetype:</b> <TMPL_VAR ESCAPE=HTML NAME=MIMETYPE>
<br><b>Size:</b> <TMPL_VAR ESCAPE=HTML NAME=SIZE>
<TMPL_IF NAME=URL><br><b><a href='<TMPL_VAR ESCAPE=URL NAME=URL><TMPL_VAR ESCAPE=URL NAME=PART>'>Download attachment</a></b>
</TMPL_IF>
END

sub addressees_data($) {

	my ($ref) = @_;
	my @data = ();
	if ($ref) {
		foreach (@{$ref}) {
			$_ =~ /^(\S*) (.*)$/;
			my %hash = (EMAIL => $1, NAME => $2);
			push(@data, \%hash);
		}
	}
	return \@data;

}

sub part_to_str($$$$);

sub part_to_str($$$$) {

	my ($pemail, $partid, $nodes, $config) = @_;

	my $part = $pemail->part($partid);
	my $type = $part->{type};

	if ( $type eq "alternative" ) {

		my $html_policy = ${$config}{html_policy};

		my $html_i;
		my $plain_i;
		my $plain_h_i;

		foreach (@{${$nodes}{$partid}}) {

			my $newpart = $pemail->part($_);
			my $mimetype = $newpart->{mimetype};

			if ( $mimetype eq "text/plain" and not $plain_i ) {
				$plain_i = $newpart->{part};
			} elsif ( $mimetype eq "text/plain-from-html" and not $plain_h_i ) {
				$plain_h_i = $newpart->{part};
			} elsif ( $mimetype eq "text/html" and not $html_i ) {
				$html_i = $newpart->{part};
			}

		}

		if ( ( $html_policy == 4 and $html_i ) or ( $html_policy == 3 and $html_i and not $plain_i ) ) {
			return part_to_str($pemail, $html_i, $nodes, $config);
		} elsif ( ( $html_policy == 2 and $plain_h_i ) or ( $html_policy == 1 and $plain_h_i and not $plain_i ) ) {
			return part_to_str($pemail, $plain_h_i, $nodes,$config);
		} elsif ( $plain_i ) {
			return part_to_str($pemail, $plain_i, $nodes, $config);
		} else {
			my $template = HTML::Template->new(scalarref => ${$config}{view_template}, die_on_bad_params => 0);
			$template->param(BODY => "Viewing html part is disabled.");
			return $template->output();
		}

	} else {

		my $template = HTML::Template->new(scalarref => ${$config}{view_template}, die_on_bad_params => 0);
		$template->param(PART => $partid);

		if ( $type eq "message" or $type eq "multipart" ) {

			my @data = ();
			my $multipart_template = HTML::Template->new(scalarref => ${$config}{multipart_template}, die_on_bad_params => 0);

			if ( $type eq "message" ) {
				my $view_template = HTML::Template->new(scalarref => ${$config}{view_template}, die_on_bad_params => 0);
				my $message_template = HTML::Template->new(scalarref => ${$config}{message_template}, die_on_bad_params => 0);
				my $header = $pemail->header($partid);
				$message_template->param(FROM => addressees_data($header->{from}));
				$message_template->param(TO => addressees_data($header->{to}));
				$message_template->param(CC => addressees_data($header->{cc}));
				$message_template->param(DATE => $header->{date});
				$message_template->param(SUBJECT => $header->{subject});
				$view_template->param(BODY => $message_template->output());
				my %hash = (PART => $view_template->output());
				push(@data, \%hash);
			}

			# If this (multipart or message) contains only one multipart, unpack it
			my $firstpart = scalar @{${$nodes}{$partid}} == 1 ? $pemail->part(${${$nodes}{$partid}}[0]) : 0;
			my $firstpart_type = $firstpart ? $firstpart->{type} : "";
			my @next_parts;

			if ( $firstpart_type eq "multipart" ) {
				@next_parts = @{${$nodes}{$firstpart->{part}}};
			} else {
				@next_parts = @{${$nodes}{$partid}};
			}

			foreach (@next_parts) {
				my %hash = (PART => part_to_str($pemail, $_, $nodes, $config));
				push(@data, \%hash);
			}

			$multipart_template->param(BODY => \@data);
			$template->param(BODY => $multipart_template->output());

		} elsif ( $type eq "view" ) {

			my $html_policy = ${$config}{html_policy};

			my $mimetype = $part->{mimetype};
			if ( $mimetype eq "text/html" and ( $html_policy == 3 or $html_policy == 2 ) ) {
				$template->param(BODY => decode_utf8($pemail->data($partid)));
			} elsif ( $mimetype eq "text/plain" or $mimetype eq "text/plain-from-html" ) {
				my $data = decode_utf8($pemail->data($partid));
				my $plaintext_template = HTML::Template->new(scalarref => ${$config}{plaintext_template}, die_on_bad_params => 0);
				$plaintext_template->param(BODY => $data);
				$template->param(BODY => $plaintext_template->output());
			} else {
				$template->param(BODY => "Error: This part cannot be shown");
			}

		} elsif ( $type eq "attachment" ) {

			my $attachment_template = HTML::Template->new(scalarref => ${$config}{attachment_template}, die_on_bad_params => 0);
			$attachment_template->param(URL => ${$config}{download_url});
			$attachment_template->param(PART => $part->{part});
			$attachment_template->param(SIZE => format_bytes($part->{size}));
			$attachment_template->param(MIMETYPE => $part->{mimetype});
			$attachment_template->param(FILENAME => $part->{filename});
			$attachment_template->param(DESCRIPTION => $part->{description});
			$template->param(BODY => $attachment_template->output());

		} else {

			$template->param(BODY => "Error: This part cannot be shown");

		}

		return $template->output();

	}

}


# config:
# html_output 0 or 1
# html_policy always(4) allow(3) strip(2) plain(1) never(0)
# time_zone origin
# date_format default
# download_url
# enabled_mime_types
# disabled_mime_types application/pgp-signature
# base_template
# message_template
# view_template
# plaintext_template
# multipart_template
# attachment_template

# to_str(pemail, config...)
sub to_str($%) {

	my ($pemail, %config) = @_;

	$config{html_output} = 1 unless $config{html_output};
	$config{html_policy} = 1 unless $config{html_policy};
	$config{html_policy} = 1 if ( $config{html_policy} < 0 || $config{html_policy} > 4 );

	# TODO: Time zone & Date format

	# TODO: Set default templates based on $html_output
	$config{disabled_mime_types} = \@disabled_mime_types_default unless $config{disabled_mime_types};
	$config{base_template} = \$base_template_default unless $config{base_template};
	$config{message_template} = \$message_template_default unless $config{message_template};
	$config{view_template} = \$view_template_default unless $config{view_template};
	$config{plaintext_template} = \$plaintext_template_default unless $config{plaintext_template};
	$config{multipart_template} = \$multipart_template_default unless $config{multipart_template};
	$config{attachment_template} = \$attachment_template_default unless $config{attachment_template};

	my @enabled_mime_types = $config{enabled_mime_types} ? @{$config{enabled_mime_types}} : ();
	my @disabled_mime_types = $config{disabled_mime_types} ? @{$config{disabled_mime_types}} : ();

	my %nodes;

	foreach (sort keys %{$pemail->parts()}) {
		my @array;
		$nodes{$_} = \@array;
	}

	foreach (sort keys %{$pemail->parts()}) {

		my $part = ${$pemail->parts()}{$_};
		my $partid = $part->{part};
		my $mimetype = $part->{mimetype};

		if ( $partid eq "0" ) { next; }
		unless ( ( scalar @enabled_mime_types > 0 and grep(/^$mimetype$/,@enabled_mime_types) ) or ( scalar @disabled_mime_types > 0 and not grep(/^$mimetype$/,@disabled_mime_types) ) ) { next; }

		my $prev = $partid;
		chop($prev);
		chop($prev);

		push(@{$nodes{$prev}}, $partid);

	}

	my $title = $pemail->header("0")->{subject};
	my $body = part_to_str($pemail, "0", \%nodes, \%config);

	my $base_template = HTML::Template->new(scalarref => $config{base_template}, die_on_bad_params => 0);
	$base_template->param(TITLE => $title);
	$base_template->param(BODY => $body);
	return $base_template->output();

}

1;
