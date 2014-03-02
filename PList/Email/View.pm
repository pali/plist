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
<meta http-equiv='Content-Type' content='text/html; charset=utf-8'>
<TMPL_IF NAME=TITLE><title><TMPL_VAR ESCAPE=HTML NAME=TITLE></title>
</TMPL_IF></head>
<body>
<TMPL_IF NAME=BODY><TMPL_VAR NAME=BODY>
</TMPL_IF></body>
</html>
END

my $address_template_default = <<END;
<a href='mailto:<TMPL_VAR ESCAPE=URL NAME=EMAIL>'><TMPL_VAR ESCAPE=HTML NAME=NAME> &lt;<TMPL_VAR ESCAPE=HTML NAME=EMAIL>&gt;</a>
END

my $subject_template_default = <<END;
<TMPL_VAR ESCAPE=HTML NAME=SUBJECT>
END

my $download_template_default = <<END;
END

my $imagepreview_template_default = <<END;
END

my $message_template_default = <<END;
<TMPL_IF NAME=FROM><b>From:</b><TMPL_LOOP NAME=FROM> <TMPL_VAR NAME=BODY>,</TMPL_LOOP><br>
</TMPL_IF><TMPL_IF NAME=TO><b>To:</b><TMPL_LOOP NAME=TO> <TMPL_VAR NAME=BODY>,</TMPL_LOOP><br>
</TMPL_IF><TMPL_IF NAME=CC><b>Cc:</b><TMPL_LOOP NAME=CC> <TMPL_VAR NAME=BODY>,</TMPL_LOOP><br>
</TMPL_IF><TMPL_IF NAME=DATE><b>Date:</b> <TMPL_VAR ESCAPE=HTML NAME=DATE><br>
</TMPL_IF><TMPL_IF NAME=SUBJECT><b>Subject:</b> <TMPL_VAR NAME=SUBJECT><br>
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
<TMPL_IF NAME=FILENAME><b>Filename:</b> <TMPL_VAR ESCAPE=HTML NAME=FILENAME><br>
</TMPL_IF><TMPL_IF NAME=DESCRIPTION><b>Description:</b> <TMPL_VAR ESCAPE=HTML NAME=DESCRIPTION><br>
</TMPL_IF><TMPL_IF NAME=MIMETYPE><b>Mimetype:</b> <TMPL_VAR ESCAPE=HTML NAME=MIMETYPE><br>
</TMPL_IF><TMPL_IF NAME=SIZE><b>Size:</b> <TMPL_VAR ESCAPE=HTML NAME=SIZE><br>
</TMPL_IF><TMPL_VAR NAME=DOWNLOAD>
END

sub addressees_data($$) {

	my ($ref, $config) = @_;
	my @data = ();
	if ($ref) {
		foreach (@{$ref}) {
			$_ =~ /^(\S*) (.*)$/;
			my $address_template = HTML::Template->new(scalarref => ${$config}{address_template}, die_on_bad_params => 0);
			$address_template->param(EMAIL => $1);
			$address_template->param(NAME => $2);
			push(@data, {BODY => $address_template->output()});
		}
	}
	return \@data;

}

sub part_to_str($$$$);

sub part_to_str($$$$) {

	my ($pemail, $partid, $nodes, $config) = @_;

	my $id = $pemail->header("0")->{id};
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
			$template->param(ID => $id);
			$template->param(PART => $partid);
			$template->param(BODY => "Viewing html part is disabled.");
			return $template->output();
		}

	} else {

		my $template = HTML::Template->new(scalarref => ${$config}{view_template}, die_on_bad_params => 0);
		$template->param(ID => $id);
		$template->param(PART => $partid);

		if ( $type eq "message" or $type eq "multipart" ) {

			my @data = ();
			my $multipart_template = HTML::Template->new(scalarref => ${$config}{multipart_template}, die_on_bad_params => 0);

			if ( $type eq "message" ) {
				my $view_template = HTML::Template->new(scalarref => ${$config}{view_template}, die_on_bad_params => 0);
				my $message_template = HTML::Template->new(scalarref => ${$config}{message_template}, die_on_bad_params => 0);
				my $subject_template = HTML::Template->new(scalarref => ${$config}{subject_template}, die_on_bad_params => 0);
				my $header = $pemail->header($partid);
				$subject_template->param(ID => $id);
				$subject_template->param(PART => $partid);
				$subject_template->param(SUBJECT => $header->{subject});
				$message_template->param(ID => $id);
				$message_template->param(PART => $partid);
				$message_template->param(FROM => addressees_data($header->{from}, $config));
				$message_template->param(TO => addressees_data($header->{to}, $config));
				$message_template->param(CC => addressees_data($header->{cc}, $config));
				$message_template->param(DATE => $header->{date});
				$message_template->param(SUBJECT => $subject_template->output());
				$view_template->param(ID => $id);
				$view_template->param(PART => $partid);
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

		} else {

			my $output;
			my $preview;
			my $textpreview;
			my $imagepreview;

			my $mimetype = $part->{mimetype};

			# TODO: Make max size of attachment configurable
			if ( $type eq "attachment" and $part->{size} <= 100000 ) {
				$preview = 1;
				if ( $mimetype ne "text/html" and $mimetype =~ /^text\// ) {
					$textpreview = 1;
				}
				if ( $mimetype =~ /^image\// ) {
					$imagepreview = 1;
				}
			}

			if ( $preview or $type eq "view" ) {

				my $html_policy = ${$config}{html_policy};

				if ( $mimetype eq "text/html" and ( $html_policy == 3 or $html_policy == 2 ) ) {
					my $data = $pemail->data($partid);
					$output = decode_utf8(${$data});
				} elsif ( $mimetype eq "text/plain" or $mimetype eq "text/plain-from-html" or $textpreview ) {
					my $data = $pemail->data($partid);
					$data = decode_utf8(${$data});
					my $plaintext_template = HTML::Template->new(scalarref => ${$config}{plaintext_template}, die_on_bad_params => 0);
					$plaintext_template->param(ID => $id);
					$plaintext_template->param(PART => $partid);
					$plaintext_template->param(BODY => $data);
					$output = $plaintext_template->output();
				}

			}

			if ( $imagepreview ) {
				my $imagepreview_template = HTML::Template->new(scalarref => ${$config}{imagepreview_template}, die_on_bad_params => 0);
				$imagepreview_template->param(ID => $id);
				$imagepreview_template->param(PART => $partid);
				$output = $imagepreview_template->output();
			}

			if ( $type eq "attachment" ) {

				my $attachment_template = HTML::Template->new(scalarref => ${$config}{attachment_template}, die_on_bad_params => 0);
				my $download_template = HTML::Template->new(scalarref => ${$config}{download_template}, die_on_bad_params => 0);
				$download_template->param(ID => $id);
				$download_template->param(PART => $partid);
				$attachment_template->param(ID => $id);
				$attachment_template->param(PART => $partid);
				$attachment_template->param(SIZE => format_bytes($part->{size}));
				$attachment_template->param(MIMETYPE => $mimetype);
				$attachment_template->param(FILENAME => $part->{filename});
				$attachment_template->param(DESCRIPTION => $part->{description});
				$attachment_template->param(DOWNLOAD => $download_template->output());

				if ( $preview and $output and length $output ) {
					my $view1_template = HTML::Template->new(scalarref => ${$config}{view_template}, die_on_bad_params => 0);
					$view1_template->param(ID => $id);
					$view1_template->param(PART => $partid);
					$view1_template->param(BODY => $attachment_template->output());
					my $view2_template = HTML::Template->new(scalarref => ${$config}{view_template}, die_on_bad_params => 0);
					$view2_template->param(ID => $id);
					$view2_template->param(PART => $partid);
					$view2_template->param(BODY => $output);
					$output = $view1_template->output() . $view2_template->output();
				} else {
					$output = $attachment_template->output();
				}

			}

			if ( not $output or not length $output ) {
				$output = "Error: This part cannot be shown";
			}

			$template->param(BODY => $output);

		}

		return $template->output();

	}

}


# config:
# html_output 0 or 1
# html_policy always(4) allow(3) strip(2) plain(1) never(0)
# time_zone origin
# date_format default
# enabled_mime_types
# disabled_mime_types application/pgp-signature
# base_template
# address_template
# subject_template
# download_template
# imagepreview_template
# message_template
# view_template
# plaintext_template
# multipart_template
# attachment_template

# to_str(pemail, config...)
sub to_str($;%) {

	my ($pemail, %config) = @_;

	$config{html_output} = 1 unless $config{html_output};
	$config{html_policy} = 1 unless $config{html_policy};
	$config{html_policy} = 1 if ( $config{html_policy} < 0 || $config{html_policy} > 4 );

	# TODO: Time zone & Date format

	# TODO: Set default templates based on $html_output
	# TODO: Add support for $html_output == 0
	$config{disabled_mime_types} = \@disabled_mime_types_default unless $config{disabled_mime_types};
	$config{base_template} = \$base_template_default unless $config{base_template};
	$config{address_template} = \$address_template_default unless $config{address_template};
	$config{subject_template} = \$subject_template_default unless $config{subject_template};
	$config{download_template} = \$download_template_default unless $config{download_template};
	$config{imagepreview_template} = \$imagepreview_template_default unless $config{imagepreview_template};
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
