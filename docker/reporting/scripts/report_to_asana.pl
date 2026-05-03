use strict;
use warnings;
use DBI;
use JSON;
use HTTP::Tiny;
use IO::Socket::SSL;
use Mozilla::CA;

# Establish DB connection
sub get_dbh {
    my ($db_host, $db_name, $db_password) = @_;
    my $db_user = 'postgres';
    my $dsn = "DBI:Pg:dbname=$db_name;host=$db_host;port=5432";
    my $dbh = DBI->connect($dsn, $db_user, $db_password, {
	RaiseError => 1,
	AutoCommit => 1,
	PrintError => 0
    });
    return $dbh;
}

# Perform Reporting Logic
sub get_feedback_report {
    my ($dbh, $table) = @_;
    
    # Use a quoted identifier to be safe
    my $quoted_table = $dbh->quote_identifier($table);
    
    my $sql = "SELECT 
                COUNT(*) FILTER (WHERE sentiment) as positive_count,
                COUNT(*) FILTER (WHERE NOT sentiment) as negative_count,
                COUNT(*) as total_count
               FROM $quoted_table 
               WHERE created_at > now() - interval '24 hours'";
               
    my ($positive, $negative, $total) = $dbh->selectrow_array($sql);

    # There should be numbers even if the result is undef
    $positive //= 0;
    $negative //= 0;
    $total    //= 0;
    
    # In case there's no feedback yet (can't calculate percentage)
    my $positive_pct = $total ? ($positive / $total) * 100 : 0;
    my $negative_pct = $total ? ($negative / $total) * 100 : 0;

    return {
        positive     => $positive,
        negative     => $negative,
        total        => $total,
        positive_pct => sprintf("%.2f%%", $positive_pct),
        negative_pct => sprintf("%.2f%%", $negative_pct),
    };
}

sub generate_notes {
    my ($report) = @_;

    # Generate nice looking report
    my $notes = sprintf(
        "Feedback analysis (Past 24 Hours)\n" .
        "==================================\n" .
        "Total Comments: %d\n\n" .
        "Positive: %d (%s)\n" .
        "Negative: %d (%s)\n" .
	"==================================\n",
        $report->{total},
        $report->{positive}, $report->{positive_pct},
        $report->{negative}, $report->{negative_pct}
    );
    return $notes
}

# Post data to Asana
sub post_to_asana {
    my ($token, $project_id, $report) = @_;
    my $notes = generate_notes($report);
    
    # Asana URL (from Asana API reference page)
    my $url = "https://app.asana.com/api/1.0/tasks";
    my $payload = encode_json({
        data => {
            projects => [$project_id],
            name     => "Daily feedback report: $report->{total} total items",
            notes    => "$notes",
        }
    });

    # Instantiate HTTP connection (enable SSL verification)
    my $http = HTTP::Tiny->new(
	verify_SSL => 1,
	SSL_options => { SSL_ca_file => Mozilla::CA::SSL_ca_file() }
    );
    
    my $response = $http->post($url, {
        headers => {
            'Authorization' => "Bearer $token",
            'Content-Type'  => 'application/json',
        },
        content => $payload
    });
    
    if (!$response->{success}) {
	die "Unable to post to Asana: $response->{status} $response->{reason}\n" . $response->{content};
    }
}

sub main {
    # DB variables
    my $db_table    = $ENV{DB_TABLE};
    my $db_host     = $ENV{DB_HOST};
    my $db_name     = $ENV{DB_NAME};
    my $db_password = $ENV{DB_PASSWORD};

    # Asana variables
    my $asana_project = $ENV{ASANA_PROJECT};
    my $asana_token   = $ENV{ASANA_TOKEN};

    eval {
	my $dbh = get_dbh($db_host, $db_name, $db_password);
	my $feedback_report = get_feedback_report($dbh, $db_table);
	
	if ($feedback_report->{total} > 0) {
	    post_to_asana($asana_token, $asana_project, $feedback_report);
	    print "Report sent to Asana successfully\n";
	} else {
	    print "No feedback found in the last 24 hours. Skipping report.\n";
	}
    };

    # The disconnection should have on its own, but double checking
    $dbh->disconnect if $dbh;
    
    if ($@) {
	warn "Reporting job failed: $@";
	exit 1;
    }

    exit 0;
}

# Everything starts here
main();
