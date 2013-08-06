[% DEFAULT
  charset = 'utf-8'
  title = 'JCVI'
  home_page = 'http://www.jcvi.org'
%]

<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="[% charset %]">
    <title>[% title %]</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="description" content="">
    <meta name="author" content="">

    <!-- CSS styles -->
    <style>
      body {
        padding-top: 125px; /* 125px to make the container go all the way to the bottom of the topbar */
      }
      /* Wrapper for page content to push down footer */
      #wrap {
        min-height: 100%;
        height: auto !important;
        height: 100%;
        /* Negative indent footer by it's height */
        margin: 0 auto -60px;
      }

      /* Set the fixed height of the footer here */
      #push,
      #footer {
        height: 60px;
      }
      #footer {
        background-color: #f5f5f5;
      }

      /* Lastly, apply responsive CSS fixes as necessary */
      @media (max-width: 767px) {
        #footer {
          margin-left: -20px;
          margin-right: -20px;
          padding-left: 20px;
          padding-right: 20px;
        }
      }
    </style>
    <link rel="stylesheet" href="http://fonts.googleapis.com/css?family=Droid+Sans:regular,bold|Inconsolata|PT+Sans:400,700" />
    <link rel="stylesheet" href="/eucap/include/bootstrap/css/bootstrap.min.css" />
    <link rel="stylesheet" href="/eucap/include/bootstrap/css/bootstrap-responsive.min.css" />

    [%- FOREACH stylesheet IN stylesheets -%]
    <link rel="stylesheet" href="[% stylesheet %]" />

    [%- END -%]

    <!-- Javascripts -->

    [%- FOREACH javascript IN javascripts -%]
    <script src="[% javascript %]" type="text/javascript"></script>

    [%- END -%]

    <!-- HTML5 shim, for IE6-8 support of HTML5 elements -->
    <!--[if lt IE 9]>
      <script src="http://html5shim.googlecode.com/svn/trunk/html5.js"></script>
    <![endif]-->

    <!-- favicon -->
    <link rel="shortcut icon" href="http://www.jcvi.org/common/images/favicon.ico">
  </head>

  <body>
  <noscript>
      <div id="browser-warning" class="alert">
          <strong>Your browser doesn't have javascript enabled!</strong> EuCAP and many other modern websites need javascript to function properly.
          We suggest you <a target="_blank" href="http://www.activatejavascript.org/">enable it</a> so that you can get the most out of the web.
      </div>
  </noscript>
  <div id="wrap">
    <div class="navbar navbar-fixed-top">
      <div id="header">
        <div id="whitepad">&nbsp;</div>
        <div id="bluepad">&nbsp;</div>
        <div id="headerContainer">
          <div id="headerContainerContainer">
            <div id="logo">
              <a href="http://www.jcvi.org">
                <img alt="J. Craig Venter Institute" src="http://www.jcvi.org/common/images/header-logo.png" class="headerImage">
              </a>
            </div>
            <div id="curve">&nbsp;</div>
            <div id="project"><table><tbody><tr>
              <td><img width="50px" src="/medicago-v35/include/images/mtr_leaf.png"></td>
              <td style="color: white; ">&nbsp;<em>Medicago truncatula</em> v3.5 Release</td>
              </tr></tbody></table>
            </div>
          </div> <!-- end headerContainerContainer -->
        </div> <!-- end headerContainer -->
      </div> <!-- end header -->
      <div class="navbar-inner">
        <div class="container">
          <a class="btn btn-navbar" data-toggle="collapse" data-target=".nav-collapse">
            <span class="icon-bar"></span>
            <span class="icon-bar"></span>
            <span class="icon-bar"></span>
          </a>
          <a class="brand" href="/eucap"><i class="icon-eucap-thumb"></i> EuCAP</a>
          <div class="nav-collapse collapse">
            <ul class="nav">
              <li><a href="http://www.jcvi.org"><i class="icon-th-large"></i> JCVI</a></li>
              [%- IF site -%]
              <li><a href="/medicago"><i class="icon-home"></i> [% site %] Home</a></li>
              [%- END -%]
            [%- IF login -%]
            </ul>
            <form class="navbar-form pull-right" action="/cgi-bin/eucap/eucap.pl" method="post">
              <input type="hidden" id="action" name="action" value="dashboard" />
              <input class="span2" type="text" name="username" id="username" placeholder="Username" />
              <input class="span2" type="password" name="password" id="password" placeholder="Password" />
              <input type="submit" class="btn btn-primary" value="Sign in" />
	          <a href="/cgi-bin/eucap/eucap.pl?action=signup_page" class="btn btn-info">Sign Up</a>
            </form>
            [%- ELSE -%]
        	<li class="dropdown">
			  	<a href="#" class="dropdown-toggle" data-toggle="dropdown"><i class="icon-tasks"></i> Dashboard <b class="caret"></b></a>
			    <ul class="dropdown-menu">
				    [%- IF is_family_editor -%]<li><a href="/cgi-bin/eucap/eucap.pl?action=dashboard">Annotate Gene Families</a></li>[%- END -%]
				    <li><a href="/cgi-bin/eucap/eucap.pl?action=dashboard&loci_panel=1">Annotate Gene Loci</a></li>
				    <li><a href="/cgi-bin/eucap/eucap.pl?action=dashboard&mutant_panel=1">Annotate Mutants</a></li>
				</ul>
			</li>
			</ul>
			<ul class="nav pull-right">
			    <li class="dropdown">
			    	<a href="#" class="dropdown-toggle" data-toggle="dropdown"><i class="icon-user"></i>&nbsp;
			    	<span id="user_username" name="user_username">[% user_info.username %]</span>&nbsp;<b class="caret"></b></a>
				    <ul class="dropdown-menu">
				    	<li class="nav-header"><span id="user_name" name="user_name">[% user_info.name %]</span><br />
						<img class="img-rounded" id="user_photo_thumb" name="user_photo_thumb" src="http://www.gravatar.com/avatar/[% user_info.email_hash %]?d=identicon&r=PG" /></li>
				    	[%- IF user_info.organization -%]<li><a href="#" id="user_org" name="user_org">[% user_info.organization %]</a></li>[%- END -%]
				    	<li><a href="mailto:[% user_info.email %]" id="user_email" name="user_email">[% user_info.email %]</a></li>
				    	[%- IF user_info.url -%]<li><a href="[% user_info.url %]" target="_blank" id="user_url" name="user_url">[% user_info.url %]</a></li>[%- END -%]
				    	<li class="divider"></li>
					    <li><a href="/cgi-bin/eucap/eucap.pl?action=edit_profile"><i class="icon-edit"></i> Edit Profile</a></li>
					    <li><a href="/cgi-bin/eucap/eucap.pl?action=logout"><i class="icon-off"></i> Logout</a></li>
				    </ul>
			    </li>
			</ul>
            [%- END -%]
          </div><!--/.nav-collapse -->
        </div> <!-- end container -->
      </div> <!-- end navbar.inner -->
    </div> <!-- end navbar -->

    <div class="container">
        <div class="page_header">
          <h2>[% page_header %]</h2>
        </div>
        [% main_content %]

    </div> <!-- /container -->
    <div id="push"></div>
  </div> <!-- end wrap -->

  <div id="footer">
      <div class="container">
          <ul class="breadcrumb">
            <li><a href=/eucap>EuCAP</a></li>
            [%- FOREACH link IN breadcrumb -%]
            <li><span class="divider">/</span> <a href="[% link.link %]">[% link.menu_name %]</a></li>
            [%- END -%]
          </ul>
      </div> <!-- /container -->
  </div> <!-- footer -->

  <!-- Bootstrap javascript
  ================================================== -->
  <!-- Placed at the end of the document so the pages load faster -->
  <script src="/eucap/include/bootstrap/js/bootstrap.min.js"></script>
  <!--script src="/eucap/include/bootstrap/js/bootstrap-transition.js"></script>
  <script src="/eucap/include/bootstrap/js/bootstrap-alert.js"></script>
  <script src="/eucap/include/bootstrap/js/bootstrap-dropdown.js"></script>
  <script src="/eucap/include/bootstrap/js/bootstrap-tab.js"></script>
  <script src="/eucap/include/bootstrap/js/bootstrap-collapse.js"></script-->
</body>
</html>
