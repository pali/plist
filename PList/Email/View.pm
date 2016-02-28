#    PList - software for archiving and formatting emails from mailing lists
#    Copyright (C) 2014-2015  Pali Rohár <pali.rohar@gmail.com>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License along
#    with this program; if not, write to the Free Software Foundation, Inc.,
#    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

package PList::Email::View;

use strict;
use warnings;

use PList::Email;
use PList::Template;

use Date::Format;

use Encode qw(decode_utf8);

use HTML::FromText;

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
<!DOCTYPE html
	PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"
	 "http://www.w3.org/TR/html4/loose.dtd">
<html>
<head>
<meta http-equiv='Content-Type' content='text/html; charset=utf-8'>
<TMPL_IF NAME=STYLEURL><link rel='stylesheet' type='text/css' href='<TMPL_VAR NAME=STYLEURL>'>
<TMPL_ELSE><TMPL_IF NAME=STYLE><style type='text/css'>
<TMPL_VAR NAME=STYLE></style>
</TMPL_IF></TMPL_IF><TMPL_IF NAME=TITLE><title><TMPL_VAR ESCAPE=HTML NAME=TITLE></title>
</TMPL_IF></head>
<body>
<TMPL_IF NAME=BODY><TMPL_VAR NAME=BODY></TMPL_IF></body>
</html>
END

my $base_template_plain_default = "<TMPL_IF NAME=BODY><TMPL_VAR NAME=BODY></TMPL_IF>";

my $style_template_default = <<END;
a {
	text-decoration: none;
}
a:hover {
	background-color: yellow;
}
div.view {
	margin: 5px;
	padding: 5px;
	border: 1px solid;
}
pre.plaintext, pre.plaintextmonospace {
	white-space: pre-wrap;			/* css-3 */
	white-space: -moz-pre-wrap !important;	/* Mozilla, since 1999 */
	white-space: -pre-wrap;			/* Opera 4-6 */
	white-space: -o-pre-wrap;		/* Opera 7 */
	word-wrap: break-word;			/* Internet Explorer 5.5+ */
	margin: 0px 0px 0px 0px;
}
pre.plaintext {
	font-family: inherit;
}
pre.plaintextmonospace {
	font-family: monospace;
}
END

my $address_template_default = "<a href='mailto:<TMPL_VAR ESCAPE=URL NAME=EMAILURL>'><TMPL_VAR ESCAPE=HTML NAME=NAME> &lt;<TMPL_VAR ESCAPE=HTML NAME=EMAIL>&gt;</a>";

my $address_template_plain_default = "<TMPL_VAR NAME=NAME> <<TMPL_VAR NAME=EMAIL>>";

my $subject_template_default = "<TMPL_VAR ESCAPE=HTML NAME=SUBJECT>";

my $subject_template_plain_default = "<TMPL_VAR NAME=SUBJECT>";

my $reply_template_default = "";

my $download_template_default = "";

my $imagepreview_template_default = "";

my $message_template_default = <<END;
<TMPL_IF NAME=FROM><b>From:</b><TMPL_LOOP NAME=FROM> <TMPL_VAR NAME=BODY><TMPL_UNLESS NAME=__last__>,</TMPL_UNLESS></TMPL_LOOP><br>
</TMPL_IF><TMPL_IF NAME=TO><b>To:</b><TMPL_LOOP NAME=TO> <TMPL_VAR NAME=BODY><TMPL_UNLESS NAME=__last__>,</TMPL_UNLESS></TMPL_LOOP><br>
</TMPL_IF><TMPL_IF NAME=CC><b>Cc:</b><TMPL_LOOP NAME=CC> <TMPL_VAR NAME=BODY><TMPL_UNLESS NAME=__last__>,</TMPL_UNLESS></TMPL_LOOP><br>
</TMPL_IF><TMPL_IF NAME=REPLYTO><b>Reply to:</b><TMPL_LOOP NAME=REPLYTO> <TMPL_VAR NAME=BODY><TMPL_UNLESS NAME=__last__>,</TMPL_UNLESS></TMPL_LOOP><br>
</TMPL_IF><TMPL_IF NAME=DATE><b>Date:</b> <TMPL_VAR ESCAPE=HTML NAME=DATE><br>
</TMPL_IF><TMPL_IF NAME=SUBJECT><b>Subject:</b> <TMPL_VAR NAME=SUBJECT><br>
</TMPL_IF><TMPL_IF NAME=ID><b>Message-Id:</b> <TMPL_VAR ESCAPE=HTML NAME=ID><br>
</TMPL_IF>
END
chomp($message_template_default);

my $message_template_plain_default = <<END;
<TMPL_IF NAME=FROM>From:<TMPL_LOOP NAME=FROM> <TMPL_VAR NAME=BODY><TMPL_UNLESS NAME=__last__>,</TMPL_UNLESS></TMPL_LOOP>
</TMPL_IF><TMPL_IF NAME=TO>To:<TMPL_LOOP NAME=TO> <TMPL_VAR NAME=BODY><TMPL_UNLESS NAME=__last__>,</TMPL_UNLESS></TMPL_LOOP>
</TMPL_IF><TMPL_IF NAME=CC>Cc:<TMPL_LOOP NAME=CC> <TMPL_VAR NAME=BODY><TMPL_UNLESS NAME=__last__>,</TMPL_UNLESS></TMPL_LOOP>
</TMPL_IF><TMPL_IF NAME=REPLYTO>Reply to:<TMPL_LOOP NAME=REPLYTO> <TMPL_VAR NAME=BODY><TMPL_UNLESS NAME=__last__>,</TMPL_UNLESS></TMPL_LOOP>
</TMPL_IF><TMPL_IF NAME=DATE>Date: <TMPL_VAR NAME=DATE>
</TMPL_IF><TMPL_IF NAME=SUBJECT>Subject: <TMPL_VAR NAME=SUBJECT>
</TMPL_IF><TMPL_IF NAME=ID>Message-Id: <TMPL_VAR NAME=ID>
</TMPL_IF>
END

my $view_template_default = <<END;
<TMPL_IF NAME=BODY><div class='view'>
<TMPL_VAR NAME=BODY></div></TMPL_IF>
END

my $view_template_plain_default = "<TMPL_IF NAME=BODY><TMPL_VAR NAME=BODY></TMPL_IF>";

my $plaintext_template_default = <<END;
<TMPL_IF NAME=BODY><pre class='plaintext'><TMPL_VAR ESCAPE=HTML NAME=BODY></pre></TMPL_IF>
END
chomp($plaintext_template_default);

my $plaintextmonospace_template_default = <<END;
<TMPL_IF NAME=BODY><pre class='plaintextmonospace'><TMPL_VAR ESCAPE=HTML NAME=BODY></pre></TMPL_IF>
END
chomp($plaintextmonospace_template_default);

my $plaintext_template_plain_default = "<TMPL_VAR NAME=BODY>";

my $multipart_template_default = "<TMPL_IF NAME=BODY><TMPL_LOOP NAME=BODY><TMPL_VAR NAME=PART></TMPL_LOOP></TMPL_IF>";

my $multipart_template_plain_default = "<TMPL_IF NAME=BODY><TMPL_LOOP NAME=BODY><TMPL_VAR NAME=PART></TMPL_LOOP></TMPL_IF>";

my $attachment_template_default = <<END;
<TMPL_IF NAME=FILENAME><b>Filename:</b> <TMPL_VAR ESCAPE=HTML NAME=FILENAME><br>
</TMPL_IF><TMPL_IF NAME=DESCRIPTION><b>Description:</b> <TMPL_VAR ESCAPE=HTML NAME=DESCRIPTION><br>
</TMPL_IF><TMPL_IF NAME=MIMETYPE><b>Mimetype:</b> <TMPL_VAR ESCAPE=HTML NAME=MIMETYPE><br>
</TMPL_IF><TMPL_IF NAME=SIZE><b>Size:</b> <TMPL_VAR ESCAPE=HTML NAME=SIZE><br>
</TMPL_IF><TMPL_VAR NAME=DOWNLOAD>
END
chomp($attachment_template_default);

my $attachment_template_plain_default = "Attachment: <TMPL_VAR NAME=FILENAME> <TMPL_IF NAME=DESCRIPTION>(<TMPL_VAR NAME=DESCRIPTION>) </TMPL_IF><TMPL_VAR NAME=MIMETYPE> <TMPL_VAR NAME=SIZE>\n";

sub addressees_data($$) {

	my ($ref, $config) = @_;
	my @data = ();
	if ( $ref ) {
		foreach ( @{$ref} ) {
			$_ =~ /^(\S*) (.*)$/;
			my $address_template = PList::Template->new(${$config}{address_template}, ${$config}{templatedir});
			$address_template->param(EMAIL => $1);
			$address_template->param(EMAILURL => $1);
			$address_template->param(NAME => $2);
			$address_template->param(NAMEURL => $2);
			push(@data, {BODY => $address_template->output()});
		}
	}
	return \@data;

}

sub date($$) {

	my ($epoch, $config) = @_;
	return undef unless $epoch;
	return time2str(${$config}{date_format}, $epoch, ${$config}{time_zone});

}

sub part_to_str($$$$$);

sub part_to_str($$$$$) {

	my ($pemail, $partid, $isroot, $nodes, $config) = @_;

	my $id = $pemail->id();
	my $part = $pemail->part($partid);
	my $type = $part->{type};

	if ( $type eq "alternative" ) {

		my $html_policy = ${$config}{html_policy};

		my $html_i;
		my $plain_i;
		my $plain_h_i;

		foreach ( @{${$nodes}{$partid}} ) {

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
			return part_to_str($pemail, $html_i, 0, $nodes, $config);
		} elsif ( ( $html_policy == 2 and $plain_h_i ) or ( $html_policy == 1 and $plain_h_i and not $plain_i ) ) {
			return part_to_str($pemail, $plain_h_i, 0, $nodes, $config);
		} elsif ( $plain_i ) {
			return part_to_str($pemail, $plain_i, 0, $nodes, $config);
		} else {
			my $template = PList::Template->new(${$config}{view_template}, ${$config}{templatedir});
			$template->param(ID => $id);
			$template->param(PART => $partid);
			$template->param(BODY => "Viewing html part is disabled.");
			return $template->output();
		}

	} else {

		my $template = PList::Template->new(${$config}{view_template}, ${$config}{templatedir});
		$template->param(ID => $id);
		$template->param(PART => $partid);

		if ( $type eq "message" or $type eq "multipart" ) {

			my @data = ();
			my $multipart_template = PList::Template->new(${$config}{multipart_template}, ${$config}{templatedir});

			if ( $type eq "message" ) {
				my $view_template = PList::Template->new(${$config}{view_template}, ${$config}{templatedir});
				my $message_template = PList::Template->new(${$config}{message_template}, ${$config}{templatedir});
				my $subject_template = PList::Template->new(${$config}{subject_template}, ${$config}{templatedir});
				my $header = $pemail->header($partid);
				my $subject = $header->{subject};
				$subject = "unknown" unless $subject;
				$subject_template->param(ID => $id);
				$subject_template->param(PART => $partid);
				$subject_template->param(SUBJECT => $subject);
				$message_template->param(ID => $id);
				$message_template->param(PART => $partid);
				$message_template->param(FROM => addressees_data($header->{from}, $config));
				$message_template->param(TO => addressees_data($header->{to}, $config));
				$message_template->param(CC => addressees_data($header->{cc}, $config));
				$message_template->param(REPLYTO => addressees_data($header->{replyto}, $config));
				$message_template->param(DATE => date($header->{date}, $config));
				$message_template->param(SUBJECT => $subject_template->output());
				if ( $isroot ) {
					my $reply_template = PList::Template->new(${$config}{reply_template}, ${$config}{templatedir});
					$reply_template->param(ID => $id);
					$message_template->param(REPLY => $reply_template->output());
				}
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

			foreach ( @next_parts ) {
				my %hash = (PART => part_to_str($pemail, $_, 0, $nodes, $config));
				push(@data, \%hash);
			}

			$multipart_template->param(BODY => \@data);
			$template->param(BODY => $multipart_template->output());

		} else {

			my $show_download;
			my $show_plaintext;
			my $show_htmltext;
			my $show_image;

			my $mimetype = $part->{mimetype};
			my $html_policy = ${$config}{html_policy};

			if ( $type eq "attachment" or length $part->{filename} ) {
				$show_download = 1;
			}

			# TODO: Make max size configurable
			if ( $part->{size} <= 100000 ) {
				if ( $mimetype =~ /^image\// ) {
					$show_image = 1;
				} elsif ( $mimetype eq "text/html" ) {
					$show_htmltext = 1 if $html_policy == 4 or $html_policy == 3;
				} elsif ( $mimetype =~ /^text\// or $mimetype =~ /^message\// ) {
					$show_plaintext = 1;
				}
			}

			my $output;
			my $preview;
			my $textpreview;
			my $imagepreview;

			if ( $show_htmltext ) {
				my $data = $pemail->data($partid);
				$output = decode_utf8(${$data});
			} elsif ( $show_plaintext ) {
				my $data = $pemail->data($partid);
				$data = decode_utf8(${$data});
				my $monospace = ${$config}{plain_monospace};
				if ( $monospace == 1 ) {
					if ( $mimetype eq "text/plain-from-html" ) {
						$monospace = 0;
					} else {
						# TODO: Add support for patch/diff detection
						$monospace = 2;
					}
				}
				my $plaintext_template;
				if ( $monospace ) {
					$plaintext_template = PList::Template->new(${$config}{plaintextmonospace_template}, ${$config}{templatedir});
				} else {
					$plaintext_template = PList::Template->new(${$config}{plaintext_template}, ${$config}{templatedir});
				}
				$plaintext_template->param(ID => $id);
				$plaintext_template->param(PART => $partid);
				$plaintext_template->param(BODY => $data);
				$output = $plaintext_template->output();
			} elsif ( $show_image ) {
				my $imagepreview_template = PList::Template->new(${$config}{imagepreview_template}, ${$config}{templatedir});
				$imagepreview_template->param(ID => $id);
				$imagepreview_template->param(PART => $partid);
				$output = $imagepreview_template->output();
			}

			if ( $show_download or not $output or not length $output ) {

				my $attachment_template = PList::Template->new(${$config}{attachment_template}, ${$config}{templatedir});
				my $download_template = PList::Template->new(${$config}{download_template}, ${$config}{templatedir});
				$download_template->param(ID => $id);
				$download_template->param(PART => $partid);
				$attachment_template->param(ID => $id);
				$attachment_template->param(PART => $partid);
				$attachment_template->param(SIZE => format_bytes($part->{size}));
				$attachment_template->param(MIMETYPE => $mimetype);
				$attachment_template->param(FILENAME => $part->{filename});
				$attachment_template->param(DESCRIPTION => $part->{description});
				$attachment_template->param(DOWNLOAD => $download_template->output());

				if ( $output and length $output ) {
					my $view1_template = PList::Template->new(${$config}{view_template}, ${$config}{templatedir});
					$view1_template->param(ID => $id);
					$view1_template->param(PART => $partid);
					$view1_template->param(BODY => $attachment_template->output());
					my $view2_template = PList::Template->new(${$config}{view_template}, ${$config}{templatedir});
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
# plain_onlybody 0 or 1
# plain_monospace always(2) detect(1) never(0)
# time_zone local
# date_format "%a, %d %b %Y %T %z"
# archive
# archive_url
# list_url
# style_url
# enabled_mime_types
# disabled_mime_types application/pgp-signature
# templatedir
# cgi_templates
# base_template
# style_template
# address_template
# subject_template
# reply_template
# download_template
# imagepreview_template
# message_template
# view_template
# plaintext_template
# plaintextmonospace_template
# multipart_template
# attachment_template

# to_str(pemail, config...)
sub to_str($;%) {

	my ($pemail, %config) = @_;

	$config{html_output} = 1 unless defined $config{html_output};
	$config{html_policy} = 1 unless defined $config{html_policy};
	$config{html_policy} = 1 if ( $config{html_policy} < 0 || $config{html_policy} > 4 );

	$config{plain_monospace} = 1 unless defined $config{plain_monospace};
	$config{plain_monospace} = 1 if ( $config{plain_monospace} < 0 || $config{plain_monospace} > 2 );

	# Time zone & Date format
	$config{time_zone} = undef if $config{time_zone} and $config{time_zone} eq "local";
	$config{date_format} = "%a, %d %b %Y %T %z" unless $config{date_format};

	if ( $config{cgi_templates} ) {
		$config{base_template} = "base.tmpl";
		$config{style_template} = "style.tmpl";
		$config{address_template} = "address.tmpl";
		$config{subject_template} = "subject.tmpl";
		$config{reply_template} = "reply.tmpl";
		$config{download_template} = "download.tmpl";
		$config{imagepreview_template} = "imagepreview.tmpl";
		$config{message_template} = "message.tmpl";
		$config{view_template} = "view.tmpl";
		$config{plaintext_template} = "plaintext.tmpl";
		$config{plaintextmonospace_template} = "plaintextmonospace.tmpl";
		$config{multipart_template} = "multipart.tmpl";
		$config{attachment_template} = "attachment.tmpl";
	}

	$config{disabled_mime_types} = \@disabled_mime_types_default unless defined $config{disabled_mime_types};

	$config{templatedir} = undef if defined $config{templatedir} and not -e $config{templatedir};

	if ( $config{html_output} ) {
		$config{base_template} = \$base_template_default unless defined $config{base_template} and defined $config{templatedir};
		$config{style_template} = \$style_template_default unless defined $config{style_template} and defined $config{templatedir};
		$config{address_template} = \$address_template_default unless defined $config{address_template} and defined $config{templatedir};
		$config{subject_template} = \$subject_template_default unless defined $config{subject_template} and defined $config{templatedir};
		$config{reply_template} = \$reply_template_default unless defined $config{reply_template} and defined $config{templatedir};
		$config{download_template} = \$download_template_default unless defined $config{download_template} and defined $config{templatedir};
		$config{imagepreview_template} = \$imagepreview_template_default unless defined $config{imagepreview_template} and defined $config{templatedir};
		$config{message_template} = \$message_template_default unless defined $config{message_template} and defined $config{templatedir};
		$config{view_template} = \$view_template_default unless defined $config{view_template} and defined $config{templatedir};
		$config{plaintext_template} = \$plaintext_template_default unless defined $config{plaintext_template} and defined $config{templatedir};
		$config{plaintextmonospace_template} = \$plaintextmonospace_template_default unless defined $config{plaintextmonospace_template} and defined $config{templatedir};
		$config{multipart_template} = \$multipart_template_default unless defined $config{multipart_template} and defined $config{templatedir};
		$config{attachment_template} = \$attachment_template_default unless defined $config{attachment_template} and defined $config{templatedir};
	} else {
		$config{base_template} = \$base_template_plain_default unless defined $config{base_template} and defined $config{templatedir};
		$config{style_template} = \"";
		$config{address_template} = \$address_template_plain_default unless defined $config{address_template} and defined $config{templatedir};
		$config{subject_template} = \$subject_template_plain_default unless defined $config{subject_template} and defined $config{templatedir};
		$config{reply_template} = \$reply_template_default unless defined $config{reply_template} and defined $config{templatedir};
		$config{download_template} = \$download_template_default unless defined $config{download_template} and defined $config{templatedir};
		$config{imagepreview_template} = \$imagepreview_template_default unless defined $config{imagepreview_template} and defined $config{templatedir};
		$config{message_template} = \$message_template_plain_default unless defined $config{message_template} and defined $config{templatedir};
		$config{view_template} = \$view_template_plain_default unless defined $config{view_template} and defined $config{templatedir};
		$config{plaintext_template} = \$plaintext_template_plain_default unless defined $config{plaintext_template} and defined $config{templatedir};
		$config{plaintextmonospace_template} = \$plaintext_template_plain_default unless defined $config{plaintextmonospace_template} and defined $config{templatedir};
		$config{multipart_template} = \$multipart_template_plain_default unless defined $config{multipart_template} and defined $config{templatedir};
		$config{attachment_template} = \$attachment_template_plain_default unless defined $config{attachment_template} and defined $config{templatedir};
		if ( $config{plain_onlybody} ) {
			$config{message_template} = \"";
		}
	}

	my @enabled_mime_types = $config{enabled_mime_types} ? @{$config{enabled_mime_types}} : ();
	my @disabled_mime_types = $config{disabled_mime_types} ? @{$config{disabled_mime_types}} : ();

	my %nodes;

	foreach ( sort keys %{$pemail->parts()} ) {
		my @array;
		$nodes{$_} = \@array;
	}

	foreach ( sort keys %{$pemail->parts()} ) {

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
	my $body = part_to_str($pemail, "0", 1, \%nodes, \%config);

	my $base_template = PList::Template->new($config{base_template}, $config{templatedir});

	if ( defined $config{style_url} ) {
		$base_template->param(STYLEURL => $config{style_url});
	} else {
		my $style_template = PList::Template->new($config{style_template}, $config{templatedir});
		my $style = $style_template->output();
		$base_template->param(STYLE => $style);
	}

	$base_template->param(ARCHIVE => $config{archive}) if defined $config{archive};
	$base_template->param(ARCHIVEURL => $config{archive_url}) if defined $config{archive_url};
	$base_template->param(LISTURL => $config{list_url}) if defined $config{list_url};

	$base_template->param(TITLE => $title);
	$base_template->param(BODY => $body);
	return \$base_template->output();

}

1;
