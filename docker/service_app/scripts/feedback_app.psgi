use strict;
use warnings;
use Plack::Request;
use Plack::Builder;
use JSON::MaybeXS;
use DBI;
use DBIx::Connector;
use Digest::SHA qw(sha256_hex);
use Log::Any qw($log);
use Log::Any::Adapter;

# TODO: Make sure quotes are consistent

# Logging to stdout
Log::Any::Adapter->set('Stdout');

# DB variables
my $DB_TABLE    = $ENV{DB_TABLE};
my $DB_HOST     = $ENV{DB_HOST};
my $DB_NAME     = $ENV{DB_NAME};
my $DB_PASSWORD = $ENV{DB_PASSWORD};

# Create DB connector
$log->debug("Creating DB connector");
my $dsn = "DBI:Pg:dbname=$DB_NAME;host=$DB_HOST;port=5432";
my $DB_CONN = DBIx::Connector->new($dsn, 'postgres', $DB_PASSWORD, {
    RaiseError => 1,
    AutoCommit => 1,
    PrintError => 0,
});

# Establish DB connection
sub get_dbh {
    $log->debug("Returning DB handler");
    # Use DB connection to automatically re-connect if necessary
    return $DB_CONN->dbh;
}

# Validate existence of table
sub ensure_schema {
    my ($dbh) = @_;
    $log->info("Validating schema");
    my $sql = qq{
        CREATE TABLE IF NOT EXISTS $DB_TABLE (
            id SERIAL PRIMARY KEY,
            user_comment TEXT NOT NULL,
            sentiment BOOL,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        );
    };
    $log->debug(sprintf "SQL query: %s", $sql);
    $dbh->do($sql);
}

# Render html form (takes csrf token)
sub render_form {
    my ($csrf) = @_;

    $log->debug("Rendering HTML form");
    
    # Escape to prevent cross-site scripting
    my $safe_csrf = escape_html($csrf);
    
    return <<"HTML";
<!doctype html>
<html>
<head><title>Feedback</title></head>
<body>
    <h1>Feedback Form</h1>
    <form action="/submit" method="POST">
        <input type="hidden" name="csrf_token" value="$safe_csrf">
        <label>Experience:</label>
        <select name="sentiment" required>
            <option value="1">Positive</option>
            <option value="0">Negative</option>
        </select><br><br>
        <label>Comments:</label><br>
        <textarea name="comment" rows="4" required></textarea><br>
        <button type="submit">Submit</button>
    </form>
</body>
</html>
HTML
}

# CSRF helper
sub generate_csrf {
    $log->debug("Generating CSRF");
    return sha256_hex(rand() . time() . $$);
}

# Escape html data
sub escape_html {
    my $s = shift // '';
    $log->debug(sprintf "Escaping string \"%s\"", $s);
    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    $s =~ s/"/&quot;/g;
    $s =~ s/'/&#39;/g;
    return $s;
}

my $app = sub {
    my $env = shift;
    my $req = Plack::Request->new($env);

    # Simple request logging
    $log->info(sprintf "%s %s", $req->method, $req->path_info);

    $log->debug("Creating session");
    my $session = $env->{'psgix.session'};
    
    # GET / (feedback form)
    if ($req->method eq 'GET' && $req->path_info eq '/') {
	# Store token in session
        $session->{csrf_token} ||= generate_csrf();
        return [
	    200,
	    ['Content-Type' => 'text/html'],
	    [render_form($session->{csrf_token})]
	];
    }

    # POST /submit
    if ($req->method eq 'POST' && $req->path_info eq '/submit') {
        my $params = $req->body_parameters;
	$log->info("Submitting feedback");
        
        # Basic CSRF check
	my $stored_token = $session->{csrf_token} // '';
        if (!$params->{csrf_token} || $params->{csrf_token} ne $stored_token) {
	    $log->warn("Forbidden: CSRF Failure");
            return [
		403,
		['Content-Type' => 'text/plain'],
		['Forbidden: CSRF Failure']
	    ];
        }

        eval {
            my $dbh = get_dbh();
            ensure_schema($dbh);

	    $log->info("Attempting to insert data into table");
            # Insert using placeholders	    
            my $sth = $dbh->prepare("INSERT INTO $DB_TABLE (user_comment, sentiment) VALUES (?, ?::boolean)");
            $sth->execute($params->{comment}, $params->{sentiment});
        };

        if ($@) {
            $log->error(sprintf "Database error: %s", $@);
            return [
		500,
		['Content-Type' => 'text/plain'],
		["Internal Server Error"]
	    ];
        }
	
        return [
	    302,
	    ['Location' => '/success'],
	    []
	];
    }

    if ($req->path_info eq '/success') {
	$log->info("Successfully added data into the table!");
        return [
	    200,
	    ['Content-Type' => 'text/html'],
	    ['<h1>Success!</h1><p>Thank you for your feedback</p>']
	];
    }
    
    # GET /health
    if ($req->method eq 'GET' && $req->path_info eq '/health') {
	$log->info("Checking health of the service app");
	my $dbh;
	
	#Check Connection
        eval {
            $dbh = get_dbh();
        };

        if ($@ || !defined $dbh) {
            $log->error(sprintf "Health check failed: Database connection error: %s", $@);
            return [
                500,
                ['Content-Type' => 'text/plain'],
                ["ERROR: database connection failed"]
            ];
        }

        # Check query execution (Read-only)
        my $db_ok = eval {
            $dbh->do("SELECT 1 FROM $DB_TABLE LIMIT 1");
            1;
        };

        if (!$db_ok) {
            $log->error(sprintf "Health check failed: Table verification error: %s", $@);
            return [
                400,
                ['Content-Type' => 'text/plain'],
                ["ERROR: Database table inaccessible"]
            ];
        }

        $log->info("Health check passed");
        return [
            200, 
            ['Content-Type' => 'text/plain'], 
            ["Test was successful"]
        ];
    }

    $log->info("Invalid path received. Not found")
    return [
	404,
	['Content-Type' => 'text/plain'],
	['Not Found']
    ];
};

builder {
    # Persistent even if the server restarts
    enable "Session", store => "File";
    enable "StackTrace";
    enable "ContentLength"; 
    $app;
};
