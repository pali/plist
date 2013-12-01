package PList::Email::View;

use strict;
use warnings;

use Encode qw(decode_utf8);

use PList::Email;

use HTML::Entities;
use HTML::FromText;
use HTML::Template;

my $t2h = HTML::FromText->new({lines => 1});

my @disabled_mime_types_default = qw(application/pgp-signature);

my $message_template_default = <<END;
<TMPL_IF NAME=FROM><b>From:</b> <TMPL_VAR NAME=FROM><br></TMPL_IF>
<TMPL_IF NAME=TO><b>To:</b> <TMPL_VAR NAME=TO><br></TMPL_IF>
<TMPL_IF NAME=CC><b>Cc:</b> <TMPL_VAR NAME=CC><br></TMPL_IF>
<TMPL_IF NAME=DATE><b>Date:</b> <TMPL_VAR NAME=DATE><br></TMPL_IF>
<TMPL_IF NAME=SUBJECT><b>Subject:</b> <TMPL_VAR NAME=SUBJECT><br></TMPL_IF>
<br>
<TMPL_IF NAME=BODY>
<TMPL_LOOP NAME=BODY>
<TMPL_VAR NAME=PART><br>
</TMPL_LOOP>
</TMPL_IF>
END

my $view_template_default = <<END;
<TMPL_IF NAME=BODY><TMPL_VAR NAME=BODY></TMPL_IF>
END

my $multipart_template_default = <<END;
<TMPL_IF NAME=BODY>
<TMPL_LOOP NAME=BODY>
<TMPL_VAR NAME=PART><br>
</TMPL_LOOP>
</TMPL_IF>
END

my $attachment_template_default = <<END;
<b>Filename:</b> <TMPL_VAR NAME=FILENAME><br>
<TMPL_IF NAME=DESCRIPTION><b>Description:</b> <TMPL_VAR NAME=DESCRIPTION><br></TMPL_IF>
<TMPL_IF NAME=MIMETYPE><b>Mimetype:</b> <TMPL_VAR NAME=MIMETYPE><br></TMPL_IF>
END

sub addressess_str($) {

	my ($ref) = @_;
	return unless $ref;
	my $str;
	foreach(@{$ref}) {
		$_ =~ /^(\S*) (.*)$/;
		$str .= " $2 <$1>";
	}
	return $str;

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

	} elsif ( $type eq "message" or $type eq "view" or $type eq "multipart" or $type eq "attachment" ) {

		my $html_policy = ${$config}{html_policy};
		my $html_output = ${$config}{html_output};

		my $template = HTML::Template->new(scalarref => ${$config}{"${type}_template"}, die_on_bad_params => 0);
		$template->param(PART => encode_entities($part->{part}));

		if ( $type eq "message" ) {
			my $header = $pemail->header($part->{part});
			$template->param(FROM => encode_entities(addressess_str($header->{from})));
			$template->param(TO => encode_entities(addressess_str($header->{to})));
			$template->param(CC => encode_entities(addressess_str($header->{cc})));
			$template->param(DATE => encode_entities($header->{date}));
			$template->param(SUBJECT => encode_entities($header->{subject}));
		} elsif ( $type eq "view" ) {
			my $mimetype = $part->{mimetype};
			if ( $mimetype eq "text/html" and ( $html_policy == 3 or $html_policy == 2 ) ) {
				$template->param(BODY => decode_utf8($pemail->data($part->{part})));
			} elsif ( $mimetype eq "text/plain" or $mimetype eq "text/plain-from-html" ) {
				my $data = decode_utf8($pemail->data($part->{part}));
				if ($html_output) {
					# TODO: Fix converting <TAB> to html
					$data = $t2h->parse($data);
				}
				$template->param(BODY => $data);
			} else {
				$template->param(BODY => "matrix error");
			}
		} elsif ( $type eq "attachment" ) {
			$template->param(MIMETYPE => encode_entities($part->{mimetype}));
			$template->param(FILENAME => encode_entities($part->{filename}));
			$template->param(DESCRIPTION => encode_entities($part->{description}));
		}

		if ( $type eq "message" or $type eq "multipart" ) {
			my @data = ();
			foreach (@{${$nodes}{$partid}}) {
				my %hash = (PART => part_to_str($pemail, $_, $nodes, $config));
				push(@data, \%hash);
			}
			$template->param(BODY => \@data);
		}

		return $template->output();

	}

}


# config:
# html_output 0 or 1
# html_policy always(4) allow(3) strip(2) plain(1) never(0)
# time_zone origin
# date_format default
# allowed_mime_types
# disabled_mime_types application/pgp-signature
# message_template
# view_template
# multipart_template
# attachment_template

# to_str(pemail, config...)
sub to_str($%) {

	my ($pemail, %config) = @_;

	$config{html_output} = 1 unless $config{html_output};
	$config{html_policy} = 1 unless $config{html_policy};
	$config{html_policy} = 1 if ( $config{html_policy} < 0 || $config{html_policy} > 4 );
	$config{disabled_mime_types} = \@disabled_mime_types_default unless $config{disabled_mime_types};
	$config{message_template} = \$message_template_default unless $config{message_template};
	$config{view_template} = \$view_template_default unless $config{view_template};
	$config{multipart_template} = \$multipart_template_default unless $config{multipart_template};
	$config{attachment_template} = \$attachment_template_default unless $config{attachment_template};

	my %nodes;

	foreach (sort keys %{$pemail->parts()}) {

		my $part = ${$pemail->parts()}{$_}->{part};
		if ( $part eq "0" ) { next; }

		my $prev = $part;
		chop($prev);
		chop($prev);

		if (not $nodes{$prev}) {
			my @array;
			$nodes{$prev} = \@array;
		}

		push(@{$nodes{$prev}}, $part);

	}

	return part_to_str($pemail, "0", \%nodes, \%config);

}

1;
