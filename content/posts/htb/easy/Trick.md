---
title: "Trick"
date: 2022-10-06T12:03:22-07:00
author: "Nate Fortner"
draft: false
---
# Opensource
## Initial Recon
### nmap
As is my goto for these, I ran nmap to see what was there, as well as adding `trick.htb` to my hosts file.  I used my normal script NmapAutomator (available here: [NmapAutomator](https://github.com/21y4d/nmapAutomator)) to run a battery of tests against it, including nmap (all types of scans), nikto, smtp user enum, and others.  From the results, I saw that it was running an OpenSSH 7.9 Debian ssh server on port 22 TCP, a postfix smtp server on port 25 TCP, a `BIND9` dns server on port 53 TCP and UDP, and a `nginx 1.14.2` HTTP server on port 80.  It also discovered a CVE in the ssh version, SSHtranger Things, but that seemed completely irrelavent as it only applied to SCP client.
### Webpage
I decided to visit the webpage, and it proved useless.  All it had on it was a sign up form for a mailing list, and upon testing, that literaly just dumped the data as it wasn't full setup.  At this point, I decide to just give up on this website as it didn't seem useful at all.
![Image of webpage](/media/htb/easy/trick/DefaultWebpage.png)
### dig
Since it was running a DNS server, I decided to run `dig` against its hostname.  Just based on prior events, I assumed it was using trick.htb, so I ran the command `dig axfr trick.htb @trick.htb`.  The `@trick.htb` causes it to run against the DNS server at `trick.htb`, and the `axfr` tells dig to ask for the entire zone's records.  This allows me to see an intersting record, a CNAME record pointed at `preprod-payrol.trick.htb`.  When I add this domain to my hosts file and visit it, I see a sign in portal. ![Screenshot of the sign-in page](/media/htb/easy/trick/LoginScreen.png)
### DNS fuzzing
After noticing the preprod-*.tricks.com Domain name, I was wondering if there were any other names in that space.  I used `ffuf` to do this, using the command `ffuf -fs 5480 -u http://trick.htb -H "Host: preprod-FUZZ.trick.htb" -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt`, which tries replacing the word FUZZ with all the other options, eventually finding marketing to be a valid URL.  However, for now I will let this rest and return later.
### Login Page
Now it's time to investigate this login page and see if I can figure out how to log in.  I initally begin by just entering a random username and password to see what happens, using `test test` as my login.  I don't see any obvious changes other than the "Username or password is incorrect" expected, so I decide to dive deeper with Burpsuite.  I open Burpsuite community edition, and open the browser to navigate to the site.  After loading the site, I enter a random username and password again and see how it is sent.  Looks like it is sent in plain text, to the url `/ajax.php`.
### SQL injection
Now, the next step would be to see if this field is vulnerable to SQL injections.  We could do this manually, but a far easier way to do so would be using `SQLMap`.  We could manually plug this information into SQLMap, but if we open Firefox developer tools, go to the Network tab, then try to enter a username and password, you can right click on the post request and copy it as a cURL command.  If you replace the word curl in this command with the word sqlmap, that command will work.  However, while this command will work, it's not the most useful output, so we want to add `--dbs`.  An intersting quirk is that while you CAN copy the request as a curl command from Burpsuite, it formats it strangely and makes it so the sqlmap command errors out.  The final sqlmap contain looks like this (ignoring the slash marks, I added those so I could add new lines to aid in readability): 
```bash
sqlmap 'http://preprod-payroll.trick.htb/ajax.php?action=login' -X POST \
    -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; rv:102.0) Gecko/20100101 Firefox/102.0' -H 'Accept: */*' \
    -H 'Accept-Language: en-US,en;q=0.5' -H 'Accept-Encoding: gzip, deflate' \
    -H 'Referer: http://preprod-payroll.trick.htb/login.php' \
    -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' \
    -H 'X-Requested-With: XMLHttpRequest' -H 'Origin: http://preprod-payroll.trick.htb' -H 'DNT: 1' \
    -H 'Connection: keep-alive' -H 'Cookie: PHPSESSID=olva3772p2hv5b5bkc1lvvv8jd' -H 'Sec-GPC: 1' \
    --data-raw 'username=admin&password=admin' --dbs
``` 
SQLMap goes through and does it's battery of tests, and eventually determines that it is a MySQL database (or mariaDB, there is no way to tell).  I give it some time, just selecting the defaults for all it's questions, and it take forever but it determines the names of the databases on that server.  Eventually, it determines that there is two databases, `information_schema` and `payroll_db`.  Next, let's try to find more information on a database.  `payroll_db` seems much more usefull than `information_schema`, so let's try it.   In order to do this, we will replace the `--dbs` at the end with `-D payroll_db --tables`, which will list all the tables in `payroll_db`.  Again, this takes a while, as the way these work is by basically guessing `a*`, `b*`, and so on, until it finds a character, at which point it begins brute forcing the second character and so on.
After it is done, a full 41 minutes later, a list of the tables is printed:
```
[11 tables]
+---------------------+
| position            |
| allowances          |
| attendance          |
| deductions          |
| department          |
| employee            |
| employee_deductions |
| employee_delowances |
| payroll             |
| payroll_items       |
| users               |
+---------------------+
```
Next, we need to try to decide where to go from here.  Since we are trying to sign in, let's take a look at the users table.  To do this, we replace the `--dbs`  from the original command with `--dump -T users -D payroll_db`.  After running this command, we get: 
```
Database: payroll_db
Table: users
[1 entry]
+----+-----------+---------------+------+---------+---------+-----------------------+------------+
| id | doctor_id | name          | type | address | contact | password              | username   |
+----+-----------+---------------+------+---------+---------+-----------------------+------------+
| 1  | 0         | Administrator | 1    | <blank> | <blank> | SuperGucciRainbowCake | Enemigosss |
+----+-----------+---------------+------+---------+---------+-----------------------+------------+
```
This is actually a way better result than I expected.  I was expecting to have to run john against a hash, but they store the password in plaintext.  Time to sign in.  And it's useless.  At least we have a password now.  Unfortunately, this username and password doesn't work for the SSH connection.  Let's revisit the other domain.

### Marketing
Opening this site, it appears to have PHP file that tells it what HTML file to load.  Just why.  Even worse, if I replace that url with, let's say, `..././..././..././..././..././etc/passwd`, I can dump the PASSWD file., which tells me that the user michael exists.  I decide to try to see if there is an SSH key in his folder, and there is.  By using the url `..././..././..././..././..././home/michael/.ssh/id_rsa`, I can read the contents of this file, however, it replaced the new lines with spaces.  Not the biggest deal, just tedious.  Replaced the spaces back to new lines, ran `chmod 700 id_rsa`, then `ssh -i id_rsa michael@trick.htb`.  And, it complained about invalid key file.  Looked closer, and this was a OpenSSH keyfile, not an RSA key file.  Found this command online to convert it, and it worked to ssh in afterwords: `ssh-keygen -p -N "" -m pem -f id_rsa`.
## Foothold

### Exploration
I quickly submitted the user flag, then I ran linpeas, and didn't really find much.  Though I doubted it would work, I tried PwnKit and DirtyPipez, and both failed.  After that, I ran `sudo -l`, and found out that I could run one command as root.  I can't edit that file, so that's out.  Instead, I decided to check out how fail2ban actually started.  I navigated to /etc/fail2ban, and found out I could edit action.d, which meant I could overwrite a file in there.  I changed the ssh fail2ban settings to instead of banning me, open a reverse shell to my computer.  I then used https://www.revshells.com/ to generate myself a reverse shell, plugged in in my IP and port, and for no particular reason, decided to use a python one.  Doesn't really matter which one, just pick one.  I then restarted fail2ban.  Then I just had to trigger the ssh fail2ban and it did it.  It took way more attempts than I thought it should, but it turns out they restart fail2ban and reset configs every minute, so when I finally got in I deleted the script to make it easier on later hackers.
