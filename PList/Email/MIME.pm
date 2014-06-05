package PList::Email::MIME;

use strict;
use warnings;

use vars qw($AUTOLOAD);
my $parent = "PList::Email";

use DateTime;
use DateTime::Format::Mail;

use Digest::SHA qw(sha1_hex);

use Email::Address;
use Email::MIME;
use Email::MIME::ContentType;

use Encode qw(decode decode_utf8 encode_utf8);
use Encode::Detect;

use File::MimeInfo::Magic qw(mimetype extensions);

use HTML::Strip;
use HTML::Entities qw(decode_entities);

my $first_prefix = 0;

my @generic_mimetypes = qw(application/octet-stream);

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
	my $str = $email->header("Subject");
	if ( defined $str ) {
		$str =~ s/\s/ /g;
		$str =~ s/^\s+//;
		$str =~ s/\s+$//;
		return $str;
	} else {
		return "";
	}

}

sub find_dates_received(@) {

	my @ret;
	foreach (@_) {
		$_ =~ s/.+;//;
		push(@ret, $_);
	}
	return @ret;

}

# date(email)
# email - Email::MIME
# date - int
# return - int
sub date($$) {

	my ($email, $date) = @_;

	my @headers;

	push(@headers, $email->header("Resent-Date"));
	push(@headers, find_dates_received($email->header("Received")));
	push(@headers, $email->header("Date"));

	foreach ( reverse @headers ) {
		next unless $_;
		my $datetime;
		eval { $datetime = DateTime::Format::Mail->new(loose => 1)->parse_datetime($_); };
		next unless $datetime;
		$datetime = $datetime->epoch();
		return $datetime unless $date;
		# Skip if datetime is in future or difference is more than 5 days
		next if $datetime > $date or $date - $datetime > 60*60*24*5;
		return $datetime;
	}

	# Fallback to specified received date
	return $date;

}

sub ids(@) {

	my @ret;
	push(@ret, m/<\s*([^<>]+)\s*>/g) foreach (@_);
	return map { $_ =~ s/[\s\\\/]//g; length($_) > 4 ? $_ : () } @ret;
	# NOTE: Too short ids cannot be used as unique identifier

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
	my @ids = ids($email->header("Message-Id"));
	if ( @ids ) {
		return $ids[0];
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

	my $address;

	if ( $email_address->address ) {
		$address = $email_address->address;
		$address =~ s/\s//g;
	}

	if ( not $address ) {
		$address = "nobody\@nohost";
	}

	my $name;

	if ( $email_address->name ) {
		$name = $email_address->name;
		$name =~ s/\s/ /g;
		$name =~ s/^\s+//;
		$name =~ s/\s+$//;
		$name =~ s/^'(.*)'$/$1/;
		$name =~ s/^"(.*)"$/$1/;
	}

	if ( not $name ) {
		$name = $email_address->user;
	}

	if ( not $name ) {
		$name = "nobody";
	}

	return $address . " " . $name;

}

# piper_address(email_address)
# email_address - string
# return - string
sub piper_address($) {

	my ($email_address) = @_;

	my $address;
	my $name;
	my $user;
	my $host;

	if ( $email_address =~ /^(\S+) at (\S+) \((.*)\)$/ ) {
		$user = $1;
		$host = $2;
		$name = $3;
		$user =~ s/\s//g;
		$host =~ s/\s//g;
		$name =~ s/\s/ /g;
		$name =~ s/^\s+//;
		$name =~ s/\s+$//;
		$name =~ s/^'(.*)'$/$1/;
		$name =~ s/^"(.*)"$/$1/;
	}

	if ( not $user ) {
		$user = "nobody";
	}

	if ( not $host ) {
		$host = "nohost";
	}

	if ( not $name ) {
		$name = $user;
	}

	$address = "$user\@$host";

	return $address . " " . $name;

}

# addresses(email, header)
# email - Email::MIME
# header - email header name
# return - array of strings
sub addresses($$) {

	my ($email, $header) = @_;
	my @addresses = $email->header($header);
	return piper_address($addresses[0]) if ( scalar @addresses == 1 and $addresses[0] =~ /^.+ at .+ \(.*\)$/ );
	return map { address($_) } Email::Address->parse($_) foreach(@addresses);

}

# string
sub html_strip($) {

	my ($html) = @_;

	# Replace &nbsp; by normal space
	$html =~ s/&nbsp;/ /g;

	# Add newlines before <br> and <div>
	$html =~ s/(?<=[^\n])(?=<br[^>]*>[^\n])/\n/g;
	$html =~ s/(?=<div[^>]*>)/\n/g;

	# NOTE: HTML::Strip does not support utf8 strings correctly, workaround is to decode html entities after decoding utf8 string
	# See: https://rt.cpan.org/Public/Bug/Display.html?id=42834#txn-705624
	$html = HTML::Strip->new(decode_entities => 0)->parse($html);
	$html = decode_utf8($html);
	$html = decode_entities($html);

	return $html;

}

sub subpart_get_body($$$$) {

	my ($subpart, $discrete, $composite, $charset) = @_;
	my $body;

	eval {
		$body = $subpart->body();
	} or do {
		$body = $subpart->body_raw();
	};

	return "" unless defined $body;

	# Text subparts should have specified charset, if not try to detect it
	if ( $discrete eq "text" and not $charset ) {
		$charset = "Detect";
	}

	# NOTE: if part is html, charset can be specified also in <head>, but this is now ignored
	# TODO: read charset from html <head> <meta> and change it to utf8

	# Non binary subparts are converted to utf8 with LF line ending
	if ( $charset ) {
		eval { my $newbody = decode($charset, $body); $body = $newbody; };
		$body =~ s/\r\n/\n/g;
		$body = encode_utf8($body);
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

# read_part(subpart, pemail, prefix, parentalt, partid)
# subpart - Email::MIME
# pemail - PList::Email
# prefix - string
# parentalt - int (parent part is alternative)
# partid - ref int
sub read_part($$$$$) {

	my ($subpart, $pemail, $prefix, $parentalt, $partid) = @_;

	my $discrete;
	my $composite;
	my $charset;

	{
		local $Email::MIME::ContentType::STRICT_PARAMS = 0;
		my $content_type = parse_content_type($subpart->content_type);
		if ( $content_type ) {
			$discrete = $content_type->{discrete};
			$composite = $content_type->{composite};
			my $attributes = $content_type->{attributes};
			if ( $attributes ) {
				$charset = $attributes->{charset};
			}
		}
	}

	# If parsing failed, set some generic content type
	if ( not $discrete or not $composite ) {
		$discrete = "application";
		$composite = "octet-stream";
	}

	# Method Email::MIME::ContentType::parse_content_type() return us-ascii charset when there is no content type header
	# So remove specified fake charset and later do some charset detection
	if ( not $subpart->content_type ) {
		$charset = undef;
	}

	my $partstr = "$prefix/${$partid}";
	my $filename = $subpart->filename();
	my $description = $subpart->header("Content-Description");
	my $body = subpart_get_body($subpart, $discrete, $composite, $charset);
	my $size = 0;

	# Detect and overwrite mimetype for parts which have unknown/generic mimetype
	if ( grep(/^$discrete\/$composite$/, @generic_mimetypes) ) {
		if ( open(my $fh, "<", \$body) ) {
			binmode($fh, ":raw");
			my $mimetype = mimetype($fh);
			if ( $mimetype and $mimetype =~ /^(.+)\/(.+)$/ ) {
				$discrete = $1;
				$composite = $2;
			}
			close($fh);
		}
	}

	if ( not $filename ) {
		$filename = "";
	}

	# NOTE: Whitespaces are not allowed in filename
	$filename =~ s/\s/_/g;

	my $type;
	my $unpack_html = 0;

	if ( $discrete eq "text" and $composite eq "html" ) {
		$unpack_html = 1;
	}

	if ( $discrete eq "message" and $composite eq "rfc822" ) {
		$type = "message";
	} elsif ( $discrete eq "multipart" or $subpart->subparts ) {
		if ( $composite eq "alternative" ) {
			$type = "alternative";
		} else {
			$type = "multipart";
		}
	} elsif ( not $parentalt and $discrete eq "text" and $composite eq "html" ) {
		# Every text/html part is converted into alternative part with two subparts (html and plain)
		# If parent part is already alternative, creating new alternative part is not needed
		$type = "alternative";
		$discrete = "multipart";
		$composite = "alternative";
		$unpack_html = 1;
	} else {
		my $disposition = content_disposition($subpart);
		if ( not $disposition ) {
			if ( $discrete eq "text" ) {
				$type = "view";
			} else {
				$type = "attachment";
			}
		} elsif ( $disposition eq "attachment" ) {
			$type = "attachment";
		} elsif ( $disposition eq "inline" ) {
			$type = "view";
		} else {
			$type = "attachment";
		}
	}

	# Filename and description are used only for attachments
	if ( $type ne "attachment" ) {
		$filename = undef;
		$description = undef;
	}

	# Invent some name if type is attachment
	if ( $type eq "attachment" and not $filename ) {
		my $ext = extensions("$discrete/$composite");
		if ( not $ext ) {
			$ext = "bin";
		}
		$filename = "File-$partstr.$ext";
		$filename =~ s/\//-/g;
	}

	if ( $type eq "attachment" or $type eq "view" ) {
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
		$pemail->add_data($partstr, \$body);
	}

	if ( $unpack_html ) {

		# For every text/html part create multipart/alternative (if needed) and add text/html and new text/plain (converted from html)

		my $partstr_plain;
		my $data_html;

		# New alternative part is created only if parent part is not alternative
		if ( not $parentalt ) {

			$partstr_plain = $first_prefix+1;
			$partstr_plain = "$partstr/$partstr_plain";

			$data_html = $body;

			my $partstr_html = "$partstr/$first_prefix";

			my $part_html = {
				part => $partstr_html,
				size => lengthbytes($data_html),
				type => "view",
				mimetype => "text/html",
			};

			$pemail->add_part($part_html);
			$pemail->add_data($partstr_html, \$data_html);

		} else {

			${$partid}++;
			$partstr_plain = "$prefix/${$partid}";
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
		$pemail->add_data($partstr_plain, \$data_plain);

	} elsif ( $type eq "alternative" ) {

		read_multipart($subpart, $pemail, $partstr, 1);

	} elsif ( $type eq "multipart" ) {

		read_multipart($subpart, $pemail, $partstr, 0);

	} elsif ( $type eq "message" ) {

		my $new_email;
		{
			# Method Email::MIME::new calling Email::MIME::ContentType::parse_content_type()
			# so make sure that strict parsing is turned off
			local $Email::MIME::ContentType::STRICT_PARAMS = 0;
			$new_email = new Email::MIME($body);
		}
		$pemail->read_email($new_email, $partstr);

	}

}

# read_multipart(part, pemail, prefix, alternative)
# part - Email::MIME
# pemail - PList::Email
# prefix - string
# alternative - int (part is alternative)
sub read_multipart($$$$) {

	my ($part, $pemail, $prefix, $alternative) = @_;

	my $partid = $first_prefix;

	foreach my $subpart ($part->subparts()) {
		read_part($subpart, $pemail, $prefix, $alternative, \$partid);
		$partid++;
	}

}

# read_email(pemail, email, prefix)
# pemail - PList::Email
# email - Email::MIME
# prefix - string
# date - int
sub read_email($$$;$) {

	my ($pemail, $email, $prefix, $date) = @_;

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
		date => date($email, $date),
		subject => subject($email),
	};

	$pemail->add_header($header);

	my $partid = $first_prefix;
	read_part($email, $pemail, $prefix, 0, \$partid);

}

sub maybe_init($) {

	my ($self) = @_;

	if ( not $self->{init} ) {

		$self->{init} = 1;

		my $date = $self->{date};
		my $str = $self->{str};

		my $email;
		{
			# Method Email::MIME::new calling Email::MIME::ContentType::parse_content_type()
			# so make sure that strict parsing is turned off
			local $Email::MIME::ContentType::STRICT_PARAMS = 0;
			$email = new Email::MIME($str);
		}
		if ( not defined $email ) {
			die "Error: Email::MIME returned undef";
		}

		my $part = {
			part => "$first_prefix",
			size => 0,
			type => "message",
			mimetype => "message/rfc822",
		};

		$self->add_part($part);
		$self->read_email($email, "$first_prefix", $date);

		# Consistency check
		if ( $self->{id} ne $self->header("0")->{id} ) {
			die "Error: Email::MIME reported different Message-Id header";
		}

	}

}

sub DESTROY {

}

sub AUTOLOAD {

	my $self = shift;
	my $func = $AUTOLOAD;
	my @args = @_;

	$self->maybe_init();

	$func =~ s/.*:://;

	my $super = $parent . "::" . $func;
	$self->$super(@args);

}

sub id($) {

	my ($self) = @_;
	return $self->{id};

}

sub data($$;$) {

	my ($self, $part, $ofh) = @_;
	$self->maybe_init();
	if ( $ofh ) {
		no warnings "utf8";
		return print $ofh ${$self->{datarefs}->{$part}};
	} else {
		return $self->{datarefs}->{$part};
	}

}

sub add_data($$$) {

	my ($self, $part, $data) = @_;
	${$self->{datarefs}}{$part} = $data;

}

sub from_str($) {

	my ($str) = @_;

	my $date;

	# Check if email contains MBox header line and use received date
	if ( ${$str} =~ /^From ([^\n]*)\n/ ) {
		my $line = $1;
		# Remove first MBox header line
		${$str} =~ s/^From [^\n]*\n//;
		# Remove leading '>' in each From line
		${$str} =~ s/^>(>*From )/$1/gm;
		# MBox line format: from date info
		if ( $line =~ /^\s*\S+\s*(.{24})/ ) {
			$date = $1;
			# NOTE: date must be in asctime format
			eval { $date = Time::Piece->strptime($date, "%a %b %d %T %Y"); } or do { $date = undef; };
			$date = $date->epoch() if $date;
		}
	}

	my $id;
	if ( ${$str} =~ /(\n|^)Message-Id:(.*)\n/i ) {
		my @ids = ids($2);
		$id = $ids[0] if @ids;
	}

	my $pemail = PList::Email::new("PList::Email::MIME");

	$pemail->{datarefs} = {};
	$pemail->{id} = $id;
	$pemail->{str} = $str;
	$pemail->{date} = $date;

	if ( not $id ) {
		$pemail->maybe_init();
		if ( not $pemail->header("0") ) {
			return undef;
		}
		$pemail->{id} = $pemail->header("0")->{id};
	}

	return $pemail;

}

sub from_fh($) {

	my ($fh) = @_;

	my $str;

	binmode($fh, ":raw");

	{
		local $/=undef;
		$str = <$fh>;
	}

	return from_str(\$str);

}

sub from_file($) {

	my ($filename) = @_;

	my $fh;

	if ( not open(my $fh, "<", $filename) ) {
		return undef;
	}

	my $pemail = from_fh($fh);

	close($fh);

	return $pemail;

}

1;
