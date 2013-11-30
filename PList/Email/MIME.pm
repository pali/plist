package PList::Email::MIME;

use strict;
use warnings;

use PList::Email;

use DateTime;
use DateTime::Format::Mail;

use Digest::SHA qw(sha1_hex);

use Email::Address;
use Email::MIME;
use Email::MIME::ContentType;

use Encode qw(encode_utf8);

use File::MimeInfo::Magic qw(mimetype extensions);

use HTML::Strip;

my $first_prefix = 0;

sub lengthbytes($) {

	use bytes;
	my ($str) = @_;
	return length($str);

}

# subject(email)
# email - Email::MIME
# return - string
sub subject($) {

	my ($email) = @_;
	if ( defined $email->header("Subject") ) {
		my $str = $email->header("Subject");
		$str =~ s/\s/ /g;
		$str =~ s/^\s+//;
		$str =~ s/\s+$//;
		return $str;
	} else {
		return "";
	}

}

sub find_date_received($) {

	return unless defined $_[0] and length $_[0];
	my $date = pop;
	$date =~ s/.+;//;
	$date;

}

# date(email)
# email - Email::MIME
# return - string
sub date($) {

	my ($email) = @_;
	my $header;
	my $date;

	$header = $email->header("Date") || find_date_received($email->header("Received")) || $email->header("Resent-Date");

	if ( $header and length $header ) {
		$date = DateTime::Format::Mail->parse_datetime($header);
	}

	if ( $date ) {
		return $date->strftime("%Y-%m-%d %H:%M:%S %z");
	} else {
		return "";
	}

}

sub ids(@) {

	my @ret;

	foreach (@_) {
		foreach (split(" ", $_)) {
			my $id = $_;
			$id =~ s/^\s*<(.*)>\s*$/$1/;
			$id =~ s/\s/_/g;
			push(@ret, $id);
		}
	}

	return @ret;

}

sub reply($) {

	my ($email) = @_;

	return ids($email->header("In-Reply-To"))

}

sub references($) {

	my ($email) = @_;

	return ids($email->header("References"));

}

sub messageid($) {

	my ($email) = @_;
	my $id = $email->header("Message-Id");
	# NOTE: Too short message id cannot be used ad unique identifier
	if ( $id and length($id) > 4 ) {
		$id =~ s/^\s*<(.*)>\s*$/$1/;
		# NOTE: Remove whitespace and '/' chars, so message id can be filename
		$id =~ s/\s/_/g;
		$id =~ s/\//_/g;
		return $id;
	} else {
		# Generate some stable unique message-id which is needed for indexing
		my $hash = sha1_hex($email->as_string());
		return "$hash\@nohost";
	}

}

# address(email_address)
# email_address - Email::Address
# return - string
sub address($) {

	my ($email_address) = @_;

	my $address = "nobody\@nohost";

	if ( $email_address->address ) {
		$address = $email_address->address;
		$address =~ s/\s//g;
	}

	if ( $email_address->name ) {
		my $name = $email_address->name;
		$name =~ s/\s/ /g;
		$name =~ s/^\s+//;
		$name =~ s/\s+$//;
		return $address . " " . $name;
	} else {
		return $address;
	}

}

# addresses(email, header)
# email - Email::MIME
# header - email header name
# return - array of strings
sub addresses($$) {

	my ($email, $header) = @_;
	my @addresses = $email->header($header);
	return map { address($_) } Email::Address->parse($_) foreach(@addresses);

}

# string
sub html_strip($) {

	my ($html) = @_;

	# TODO: this does not working for non ascii chars!!!
	return HTML::Strip->new()->parse($html);

}

sub subpart_get_body($$$$) {

	my ($subpart, $discrete, $composite, $charset) = @_;
	my $body;

	# body_str() will decode Content-Transfer-Encoding and charset encoding
	# it working only when charset is defined or content-type is text/html or text/plain
	# otherwise do not encode charset
	if ( defined $charset or ( $discrete eq "text" and ( $composite eq "html" or $composite eq "plain" ) ) ) {
		eval {
			$body = $subpart->body_str();
			# Convert CRLF to LF and encode to utf8
			$body =~ s/\r\n/\n/g;
			$body = encode_utf8($body);
		} or do {
			$body = $subpart->body();
		}
	} else {
		$body = $subpart->body();
	}

	return $body;

}

sub content_disposition($) {

	my ($subpart) = @_;
	my $dis = $subpart->header("Content-Disposition") || "";
	$dis =~ s/;.*//;
	return $dis;

}

# Fixing: read_multipart() called too early to check prototype
sub read_multipart($$$$);

# read_multipart(email, pemail, prefix, mimetype)
# email - Email::MIME
# pemail - PList::Email
# prefix - string
# mimetype - string (discrete/composite)
sub read_multipart($$$$) {

	my ($email, $pemail, $prefix, $mimetype) = @_;

	my $partid = $first_prefix;

	foreach my $subpart ($email->parts()) {

		my $discrete;
		my $composite;
		my $charset;

		{
			local $Email::MIME::ContentType::STRICT_PARAMS = 0;
			my $content_type = parse_content_type($subpart->content_type);
			$discrete = $content_type->{discrete};
			$composite = $content_type->{composite};
			my $attributes = $content_type->{attributes};
			$charset = $attributes->{charset};

			# If parsing failed, set some generic content type
			if ( not $discrete and not $composite ) {
				$discrete = "application";
				$composite = "octet-stream";
			}
		}

		my $partstr = "$prefix/$partid";
		my $filename = $subpart->filename();
		my $description = $subpart->header("Content-Description");
		my $body = subpart_get_body($subpart, $discrete, $composite, $charset);
		my $size = 0;

		if ( not $filename ) {
			$filename = "";
		}

		# NOTE: Whitespaces are not allowed in filename
		$filename =~ s/\s/_/g;

		my $type;

		if ( $discrete eq "message" and $composite eq "rfc822" ) {
			$type = "message";
		} elsif ( $discrete eq "multipart" or $subpart->subparts ) {
			if ( $composite eq "alternative" ) {
				$type = "alternative";
			} else {
				$type = "multipart";
			}
		} elsif ( $mimetype ne "multipart/alternative" and $discrete eq "text" and $composite eq "html" ) {
			$type = "alternative";
		} else {
			my $disposition = content_disposition($subpart);
			if ( not $disposition ) {
				if ( $discrete eq "text" ) {
					$type = "view";
				} else {
					$type = "unknown";
				}
			} elsif ( $disposition eq "attachment" ) {
				$type = "attachment";
			} elsif ( $disposition eq "inline" ) {
				$type = "view";
			} else {
				$type = "unknown";
			}
		}

		# Detect and overwrite mimetype for attachments
		if ( $type eq "attachment" ) {
			if ( open(my $fh, "<:raw", \$body) ) {
				my $mimetype_new = mimetype($fh);
				if ( $mimetype_new =~ /^(.+)\/(.+)$/ ) {
					$discrete = $1;
					$composite = $2;
				}
				close($fh);
			}
		}

		# Invent some name if type is attachment
		if ( $type eq "attachment" and $filename eq "" ) {
			my $ext = extensions("$discrete/$composite");
			if ( not $ext ) {
				$ext = "bin";
			}
			$filename = "File-$partstr.$ext";
			$filename =~ s/\//-/g;
		}

		if ( $type eq "attachment" or $type eq "view" or $type eq "unknown" ) {
			$size = lengthbytes($body);
		}

		my $part = {
			part => $partstr,
			size => $size,
			type => $type,
			mimetype => "$discrete/$composite",
			filename => $filename,
			description => $description,
		};

		$pemail->add_part($part);

		if ( $body and $size > 0 ) {
			$pemail->add_data($partstr, $body);
		}

		if ( $discrete eq "text" and $composite eq "html" ) {

			# For every text/html part create multipart/alternative and add text/html and new text/plain (converted from html)

			my $partstr_plain;
			my $data_html;

			if ( $type eq "alternative" ) {

				$partstr_plain = $first_prefix+1;
				$partstr_plain = "$partstr/$partstr_plain";

				$data_html = $subpart->body_str();

				my $partstr_html = "$partstr/$first_prefix";

				my $part_html = {
					part => $partstr_html,
					size => lengthbytes($data_html),
					type => "view",
					mimetype => "text/html",
				};

				$pemail->add_part($part_html);
				$pemail->add_data($partstr_html, $data_html);

			} else {

				$partid++;
				$partstr_plain = "$prefix/$partid";
				$data_html = $body;

			}

			my $data_plain = html_strip($data_html);

			my $part_plain = {
				part => $partstr_plain,
				size => lengthbytes($data_plain),
				type => "view",
				mimetype => "text/plain-from-html",
			};

			$pemail->add_part($part_plain);
			$pemail->add_data($partstr_plain, $data_plain);

		} elsif ( $type eq "alternative" ) {

			read_multipart($subpart, $pemail, $partstr, "$discrete/$composite");

		} elsif ( $type eq "message" ) {

			read_email(new Email::MIME($body), $pemail, $partstr);

		}

		$partid++;

	}

}

# read_email(email, pemail, prefix)
# email - Email::MIME
# pemail - PList::Email
# prefix - string
sub read_email($$$) {

	my ($email, $pemail, $prefix) = @_;

	my @from = addresses($email, "From");
	my @to = addresses($email, "To");
	my @cc = addresses($email, "Cc");
	my @reply = reply($email);
	my @references = references($email);

	my $header = {
		part => $prefix,
		from => \@from,
		to => \@to,
		cc => \@cc,
		reply => \@reply,
		references => \@references,
		id => messageid($email),
		date => date($email),
		subject => subject($email),
	};

	$pemail->add_header($header);

	my $discrete;
	my $composite;

	{
		local $Email::MIME::ContentType::STRICT_PARAMS = 0;
		my $content_type = parse_content_type($email->content_type);
		$discrete = $content_type->{discrete};
		$composite = $content_type->{composite};
	}

	if ( $discrete eq "multipart" ) {

		$prefix .= "/$first_prefix";

		my $type;

		if ( $composite eq "alternative" ) {
			$type = "alternative";
		} else {
			$type = "multipart";
		}

		my $part = {
			part => $prefix,
			size => 0,
			type => $type,
			mimetype => "$discrete/$composite",
			filename => "",
			description => "",
		};

		$pemail->add_part($part);

	}

	read_multipart($email, $pemail, $prefix, "$discrete/$composite");

}

sub data($$) {

	my ($datarefs, $part) = @_;
	return ${$datarefs}{$part};

}

sub add_data($$$) {

	my ($datarefs, $part, $data) = @_;
	${$datarefs}{$part} = $data;

}

sub from_str($) {

	my ($str) = @_;

	my %datarefs;

	my $email = new Email::MIME($str);
	if ( not defined $email ) {
		return undef;
	}

	my $pemail = PList::Email::new();
	$pemail->set_datafunc(\&data);
	$pemail->set_add_datafunc(\&add_data);
	$pemail->set_private(\%datarefs);

	my $part = {
		part => "$first_prefix",
		size => 0,
		type => "message",
		mimetype => "message/rfc822",
		filename => "",
		description => "",
	};

	$pemail->add_part($part);

	read_email($email, $pemail, "$first_prefix");
	return $pemail;

}

sub from_file($) {

	my ($filename) = @_;

	my $str;

	if ( open(my $file, "<:raw", $filename) ) {
		local $/=undef;
		$str = <$file>;
		close($file);
	} else {
		return undef;
	}

	return from_str(\$str);

}

1;
