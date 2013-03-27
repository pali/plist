package PList::Email::MIME;

use strict;
use warnings;

use Email::Address;
use Email::Date;
use Email::MIME;
use Email::MIME::ContentType;

use HTML::Strip;

use Time::Piece;

my $first_prefix = 0;

# new_from_str(str, class)
# str - string or string ref
# class
# return - self
sub new_from_str($;$) {

	my ($str, $class) = @_;

	my $email = new Email::MIME($str);
	if ( not defined $email ) {
		return undef;
	}

	my $length;
	if ( not ref($str) ) {
		$length = length($str);
	} else {
		$length = length(${$str});
	}

	my $self = {
		email => $email,
		length => $length,
	};

#	return bless $self, $class;
	return bless $self;

}

# new_from_file(filename, class)
sub new_from_file($;$) {

	my ($filename, $class) = @_;

	my $str;

	if ( open(my $file, "<:raw", $filename) ) {
		local $/=undef;
		$str = <$file>;
		close($file);
	} else {
		return undef;
	}

	return new_from_str(\$str, $class);

}

# subject(email)
# email - Email::MIME
# return - string
sub subject($) {

	my ($email) = @_;
	if ( defined $email->header("Subject") ) {
		return $email->header("Subject");
	} else {
		return "";
	}

}

# date(email)
# email - Email::MIME
# return - string
sub date($) {

	my ($email) = @_;
	my $timepiece = find_date($email);
	if ( defined $timepiece ) {
		return $timepiece->strftime();
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
	if ( $id ) {
		$id =~ s/^\s*<(.*)>\s*$/$1/;
		return $id;
	} else {
		return "";
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
	}

	if ( $email_address->name ) {
		return $address . " " . $email_address->name;
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
		} or do {
			$body = $subpart->body();
		}
	} else {
		$body = $subpart->body();
	}

	return $body;

}

# Fixing: parse_multipart() called too early to check prototype
sub parse_multipart($$$$$);

# parse_email(prefix, email, parts, headers, datarefs)
# prefix - string
# email - Email::MIME
# parts - ref to array (modify)
# headers - ref to array (modify)
# datarefs - ref to array (modify)
sub parse_multipart($$$$$) {

	my ($prefix, $email, $parts, $headers, $datarefs) = @_;

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
		}

		# TODO: do some content type correction

		my $partstr = "$prefix/$partid";
		my $filename = $subpart->filename();
		my $description = $subpart->header("Content-Description");
		my $body = subpart_get_body($subpart, $discrete, $composite, $charset);
		my $size = 0;

		my $type;

		if ( $discrete eq "message" and $composite eq "rfc822" ) {
			$type = "message";
		} elsif ( $discrete eq "multipart" or $subpart->subparts ) {
			if ( $composite eq "alternative" ) {
				$type = "alternative";
			} else {
				$type = "multipart";
			}
		} elsif ( $discrete eq "text" and $composite eq "html" ) {
			$type = "alternative";
		} else {
			my $disposition = $subpart->header("Content-Disposition");
			if ( not $disposition ) {
				if ( $discrete eq "text" ) {
					$type = "view";
				} else {
					$type = "ignore";
				}
			} elsif ( $disposition eq "attachment" ) {
				$type = "attachment";
			} elsif ( $disposition eq "inline" ) {
				$type = "view";
			} else {
				$type = "ignore";
			}
		}

		# TODO: invent some name if type is attachment

		if ( $type eq "attachment" or $type eq "view" or $type eq "ignore" ) {
			$size = length($body);
		}

		my $part = {
			part => $partstr,
			size => $size,
			type => $type,
			mimetype => "$discrete/$composite",
			filename => $filename,
			description => $description,
		};

		push(@{$parts}, $part);

		if ( $body and $size > 0 ) {
			my $dataref = {
				part => $partstr,
				dataref => \$body,
			};
			push(@{$datarefs}, $dataref);
		}

		if ( $type eq "alternative" and $discrete eq "text" and $composite eq "html" ) {

			# For every text/html part create multipart/alternative and add text/html and new text/plain (converted from html)

			my $partstr_html = "$partstr/$first_prefix";
			my $partstr_plain = $first_prefix+1;
			$partstr_plain = "$partstr/$partstr_plain";

			my $data_html = $subpart->body_str();
			my $data_plain = html_strip($data_html);

			my $part_html = {
				part => $partstr_html,
				size => length($data_html),
				type => "view",
				mimetype => "text/html",
			};

			my $part_plain = {
				part => $partstr_plain,
				size => length($data_plain),
				type => "view",
				mimetype => "text/plain",
			};

			my $dataref_html = {
				part => $partstr_html,
				dataref => \$data_html,
			};

			my $dataref_plain = {
				part => $partstr_plain,
				dataref => \$data_plain,
			};

			push(@{$parts}, ($part_html, $part_plain));
			push(@{$datarefs}, ($dataref_html, $dataref_plain));

		} elsif ( $type eq "alternative" ) {

			parse_multipart($partstr, $subpart, $parts, $headers, $datarefs);

		} elsif ( $type eq "message" ) {

			parse_email($partstr, new Email::MIME($body), $parts, $headers, $datarefs);

		}

		$partid++;

	}

}

# parse_email(prefix, email, parts, headers, datarefs)
# prefix - string
# email - Email::MIME
# parts - ref to array (modify)
# headers - ref to array (modify)
# datarefs - ref to array (modify)
sub parse_email($$$$$) {

	my ($prefix, $email, $parts, $headers, $datarefs) = @_;

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

	push(@{$headers}, $header);

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

		push(@{$parts}, $part);

	}

	parse_multipart($prefix, $email, $parts, $headers, $datarefs);

}

sub to_binary($) {

	my ($self) = @_;

	# 2^60 has less then 20 digits
	if ( $self->{length} > 2**60 ) {
		return undef;
	}

	my $bin = "";
	my %offsets;

	my @parts;
	my @headers;
	my @datarefs;

	my $prefix = "$first_prefix";

	my $part = {
		part => $prefix,
		size => 0,
		type => "message",
		mimetype => "message/rfc822",
		filename => "",
		description => "",
	};

	push(@parts, $part);

	parse_email($prefix, $self->{email}, \@parts, \@headers, \@datarefs);

	$bin .= "Parts:\n";
	foreach (@parts) {
		$bin .= " ";
		$bin .= $_->{part};
		$bin .= " ";
		$offsets{$_->{part}} = length($bin);
		# NOTE: offset is calculated when adding data, allocate 20 digits for offset
		$bin .= sprintf("%.20d", 0);
		$bin .= " ";
		$bin .= $_->{size};
		$bin .= " ";
		$bin .= $_->{type};
		$bin .= " ";
		$bin .= $_->{mimetype};
		if ( defined $_->{filename} ) {
			$bin .= " ";
			$bin .= $_->{filename};
		}
		# TODO: add description
		$bin .= "\n";
	}

	foreach (@headers) {
		$bin .= "Part:\n";
		$bin .= " $_->{part}\n";
		if ( @{$_->{from}} ) {
			$bin .= "From:\n";
			$bin .= " $_\n" foreach (@{$_->{from}});
		}
		if ( @{$_->{to}} ) {
			$bin .= "To:\n";
			$bin .= " $_\n" foreach (@{$_->{to}});
		}
		if ( @{$_->{cc}} ) {
			$bin .= "Cc:\n";
			$bin .= " $_\n" foreach (@{$_->{cc}});
		}
		if ( @{$_->{reply}} ) {
			$bin .= "Reply:\n";
			$bin .= " $_\n" foreach (@{$_->{reply}});
		}
		if ( @{$_->{references}} ) {
			$bin .= "References:\n";
			$bin .= " $_\n" foreach (@{$_->{references}});
		}
		if ( $_->{id} ) {
			$bin .= "Id:\n";
			$bin .= " $_->{id}\n";
		}
		if ( $_->{date} ) {
			$bin .= "Date:\n";
			$bin .= " $_->{date}\n";
		}
		if ( $_->{subject} ) {
			$bin .= "Subject:\n";
			$bin .= " $_->{subject}\n";
		}
	}

	$bin .= "Data:\n";
	foreach (@datarefs) {
		# NOTE: for offset we have allocated 20 digits at position $offsets{$part}
		my $offset = length($bin);
		if ( $offset >= 10**20 ) {
			return undef;
		}
		substr($bin, $offsets{$_->{part}}, 20) = sprintf("%.20d", length($bin));
		$bin .= ${$_->{dataref}};
	}

	return $bin;

}

1;
