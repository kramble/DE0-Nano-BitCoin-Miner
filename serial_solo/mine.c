// mine.c - fpgaminer serial client for raspberry pi

// NB There is no synchronisation check in the fpga code, it just assumes each
// 64 byte block of data sent to it is work. Spurious bytes will put it out of
// sync. TODO fix, and poll for results.

// TODO write to stderr rather than stdout? Or at least ensure child
// processes (send_json, though this is redirected, and sha256_generic)
// are consistent and write ONLY to stdout.

// v21 - removes redundant data from work, now 44 bytes rather than 64 sent
// v22 - fixed hacktick (I forgot to set it in v21) and reduced timeout from
//       1000s  (what was I thinking?) to 100ms
// v23 - reduce amount of logging of getwork. Also renamed IN to GN.

#include <termios.h>
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/signal.h>
#include <sys/types.h>
#include <stdint.h>		// For uint64_t
#include <errno.h>

#include "base64.h"
#include "sha256.h"

#define BAUDRATE B4800
#define MODEMDEVICE "/dev/ttyAMA0"
#define _POSIX_SOURCE 1         //POSIX compliant source
#define FALSE 0
#define TRUE 1

int gn_count;
unsigned int gnonce;
int gnonceBytes;

#define MIDSTATE_DATA_LEN 1024		// NB Used in loadwork()
char midstate[MIDSTATE_DATA_LEN];	// These transfer data between checkwork
char data[MIDSTATE_DATA_LEN];		// and loadwork

char minetmp[] = "/tmp/fpgaminer";
// char workfilename[] = "/tmp/fpgaminer/work.txt";	// Disused as of v19

char workreq_file[256];

volatile int STOP=FALSE;

void signal_handler_IO (int status);    //definition of signal handler
int wait_flag=TRUE;                     //TRUE while no signal received
char devicename[80];
long Baud_Rate = 4800;         // default Baud Rate (110 through 38400)
long BAUD;                     // derived baud rate from command line
long DATABITS;
long STOPBITS;
long PARITYON;
long PARITY;
int Data_Bits = 8;              // Number of data bits
int Stop_Bits = 1;              // Number of stop bits
int Parity = 0;                 // Parity as follows:
								// 00 = NONE, 01 = Odd, 02 = Even,
								// 03 = Mark, 04 = Space
int status = 0;

int checkworkCount;
time_t last_checkwork;

#define WORKLEN (32 + 128)	// midstate + data = 160 bytes
#define WORKSEND 44			// NB we actually send 44 bytes to fpga not full 160

// Global, so its init to 0
unsigned char work[WORKLEN];		// midstate + data
unsigned char sendwork[WORKSEND];	// midstate + bytes 64..72 of data

// Quick and dirty stack of results
#define WORKSTACKLEN 4
// NB Not using double index array as pointer arithmetic catches
// us out in memcpy
unsigned char workstack[WORKSTACKLEN*WORKLEN];

// Connection data - used in submit_work_request() and processNonce()

char *configFile;	// NB takes address of Param_strings[5]
char *url;			// Read from config file
char *passwd;

// NB format change as config file does not contain the separate '/' 
// so this is added below (grep system), also read_config replaces the ':'
// separating the port with a space, send_json copes with a trailing /
// after the port number (it uses atoi).

int read_config(char *filename)
{
	FILE *f = fopen(filename,"r");
	if (!f)
	{
		printf("read_config: ERROR opening file %s\n", filename);
		return 1;
	}

	// Use the same format as config.tcl in fpgaminer, though of course
	// we're not parsing it as TCL

	// For now, be lazy and require exact spec (no spaces)
	char buf[256];
	int got_url=0;
	int got_userpass=0;
	for(;;)
	{
		if (!fgets(buf, sizeof(buf)-1, f))
			break;

		// TODO allow for missing http:// prefix.
		if (!strncmp(buf,"set url \"http://",16))
		{
			// NB We strip out the http:// prefix as it confuses send_json
			int len = strlen(buf)+8;	// This will pe plenty (NB we do need
										// the extra in case there is no
										// http prefix to strip and we have
										// to add a " /" to the end)
			url = malloc(len);			// NB global (we won't bother with free)
			if (!url)
			{
				printf("read_config: ERROR malloc, ABORT\n");
				fclose(f);
				exit(1);
			}
			strcpy(url, buf+16);
			// printf("url=<%s>\n",url);
			// Strip off the final quote
			char *p = url;
			while(*p && *p!='"') p++;
			if (*p)
			{
				*p = 0;
			}
			else
			{
				printf("read_config: ERROR url did not have final quote char\n");
				fclose(f);
				return 1;
			}

			// We need the port to be separated by a space, not a ':'
			// else would have to modify send_json, so do that here
			p = url + strlen(url);	// Start at the back
			while (p > url)
			{
				// Don't bother error checking for the moment
				// The worst outcome is thet send_json refuses it
				if (*p == ':')
				{
					*p=' ';
					break;
				}
				p--;
			}

			// Separate the filename from the server:port, we start
			// scanning from the colon (above)
			while (*p && *p != '/') p++;
			if (*p=='/')
			{
				memmove(p+1, p, strlen(p)+1);
				*p = ' ';
			}
			else
			{
				// There was no '/' after the port, so append one else
				// send_json will abort. There is plenty of room as we
				// malloc'd extra space.
				strcat(url," /");
			}
			got_url = 1;
			continue;
		}

		if (!strncmp(buf,"set userpass \"",14))
		{
			int len = strlen(buf) - 13;
			passwd = malloc(len);		// NB global (we won't bother with free)
			if (!passwd)
			{
				printf("read_config: ERROR malloc, ABORT\n");
				fclose(f);
				exit(1);
			}
			strcpy(passwd, buf+14);

			// Strip off the final quote
			char *p = passwd;
			while(*p && *p!='"') p++;
			if (*p)
			{
				*p = 0;
			}
			else
			{
				printf("read_config: ERROR userpass did not have final quote char\n");
				fclose(f);
				return 1;
			}

			got_userpass = 1;
			continue;
		}
	} // End for

	fclose(f);
	if (got_url && got_userpass)
		return 0;	// Success

	printf("read_config: ERROR parsing %s, need exact formatting (see example)\n", filename);
	return 1;	
}

int	submit_work_request(char *file)
{
	char command[256];
	// NB run the submission in the background, so as not to hang
	sprintf(command,"./send_json %s %s getwork >>%s 2>&1&", url, passwd, file);
	// DEBUG print command (NOT done in live as its too noisy)
	// printf("system %s\n",command, file); fflush(stdout);
	int res = system(command);
	checkworkCount = 0;	// Reset counter
	return 0;
}

int getwork()
{
	time_t now;
	time(&now);
	char tmpfile[256];
	sprintf(tmpfile,"%s/work_%u",minetmp,now);
	strcpy(workreq_file, tmpfile);
	printf("getwork tmpfile %s\n",tmpfile);
	submit_work_request(tmpfile);
	return 0;
}

int json_find(char *out, char *buf, char *name)
// This is the NEW stratum version which has all items on same line
// NB This assumes both the item name and value are quoted, BUT some
// items (error, id) have unquoted values. The current code WILL NOT WORK
// if we try to lookup these values (but we don't so its not a problem).
{
	char *p = buf;
	int state = 1;
	while (*p)
	{
		// This really ought to be a switch() - TODO
		if (state == 1)	// search for a quote
		{
			while (*p && (*p != '"'))
				p++;
			p++;
			state++;
		}
		else if (state == 2)
		{
			if (strncmp(p,name,strlen(name)))
			{
				p++;
				state = 1;	// Keep looking
				continue;
			}
			p+=strlen(name);
			state++;
		}
		else if (state == 3)
		{
			if (*p != '"')
				return state + 100;
			p++;
			state++;
		}
		else if (state == 4)
		{
			while (*p && isspace(*p))
				p++;
			state++;
		}
		else if (state == 5)
		{
			if (*p != ':')
				return state + 100;
			p++;
			state++;
		}
		else if (state == 6)
		{
			while (*p && isspace(*p))
				p++;
			state++;
		}
		else if (state == 7)
		{
			if (*p != '"')
				return state + 100;
			p++;
			state++;
		}
		else if (state == 8)
		{
			while (*p && *p!='"')
			{
				*out++ = *p++;
			}
			*out = 0;
			if (*p == '"')
				return 0;	// SUCCESS
			return state + 100;		// Data is incomplete, try later
		}
	}

	return state + 100;	// Fail
}

int checkwork()
{
	time_t now;
	time(&now);
	if (now < last_checkwork + 1)
		return 1;	// Do not check more than once per second
	last_checkwork = now;

	// FILE *f = fopen("work.stratum", "r");	// TEST using local file
	FILE *f = fopen(workreq_file, "r");
	if (!f)
	{
		// NB This is to be expected as file is not created until child
		// child process starts, so ignore the first error
		if (checkworkCount++)
			printf("checkwork: ERROR opening file %s\n", workreq_file);
		return 2;
	}
	else
	{
		// printf("checkwork: INFO opened file %s", workreq_file);	// No \n
	}

	// Use larger buffer for stratum as data is all on one line (original 1024
	// bytes worked but prefer larger one for safety)
	char buf[8192] = { };	// MUST clear it else get WIERD bug vis midstate
						    // and data are not updated after first getwork.
							// Its due to old data not being cleared from
							// stack, so we see the old data and match on it
							// Should not happen, but maybe a bug in json_find
							// scans beyond initial null terminator?

	int got_midstate=0;
	int got_data=0;

	// v19 removing workfile - moved midstate and data to globals
	memset(midstate, 0, sizeof(midstate));	// We originally init'd them
	memset(data, 0, sizeof(data));			// to 0, so keep that behaviour

	for(;;)
	{
		int ret = 0;
		if (!fgets(buf, sizeof(buf)-1, f))
			break;
		if (!(ret=json_find(midstate, buf, "midstate")))
		{
			got_midstate = 1;
			// printf("mid=%s\n",midstate);	// DEBUG
		}
		if (!(ret=json_find(data, buf, "data")))
			got_data = 1;

		if (got_midstate && got_data)
		{
			fclose(f);
			workreq_file[0] = 0;	// Clear file (acts as flag)
			printf("checkwork: SUCCESS loaded work\n");
			return 0;	// Success
		}
		// printf("state=%d :%s\n", ret, buf);
	}

	fclose(f);
	// printf(" INCOMPLETE\n");
	return 1;	// Not found
}

int loadwork()
{
	// Load test work data = midstate + data (reads hex strings)

	// printf("mid=%s dat=%s\n", midstate, data);

	// Kludge so we don't have to rewrite code
	char indata[MIDSTATE_DATA_LEN*2]; // Size of midstate + data
	strcpy(indata,midstate);
	strcat(indata,data);
	char *pindata = indata;

	char *p = work;
	int count = 0;
	int ch;		// NOT char
	int byte = 0;
	int nibble = 0;

	// while((ch=fgetc(fw))!=EOF)	// Disused as of v19
	while(ch=*pindata++)
	{
		if (ch=='\r' || ch=='\n')
			break;

		if (!isxdigit(ch))
		{
			// fclose(fw);		// Disused as of v19
			return 3;
		}

		ch = toupper(ch);
		int unhex = ch - '0';
		if (unhex > 9)
			unhex -= ('A' - '0' - 10);

		if (nibble)
		{
			count++;
			if (count > sizeof(work))
			{
				// Belt and braces check for array overflow
				printf("loadwork: ERROR count=%d (ARRAY OVERFLOW)\n", count);
				// fclose(fw);		// Disused as of v19
				return 2;	// WAY too much data
			}

			if (count > WORKLEN)
			{
				printf("loadwork: ERROR count=%d (>WORKLEN) ch=%c\n", count, ch);
				// fclose(fw);		// Disused as of v19
				return 2;	// Too much data
			}

			*p++ = (byte | unhex);
			byte = 0;
			nibble = 0;
		}
		else
		{
			byte = unhex <<4;
			nibble = 1;
		}
	}

	// Load data into sendwork in reverse order
	int i;
	for (i=0; i<32; i++)
		sendwork[i] = work[31-i];	// Midstate

	for (i=32; i<44; i++)
		sendwork[i] = work[139-i];	// Bytes 64..72 of data, ie first 12 bytes
									// of second 64 bytes of data, the rest
									// is const (mostly zeros except for a one
									// bit flag and the hash message length=80

	// Shift the stack
	int len = WORKLEN;
	for (i=0; i<WORKSTACKLEN-1; i++)
	{
		memcpy(workstack + i*len, workstack + (i+1)*len, len);
	}
	memcpy(workstack + (WORKSTACKLEN-1)*len, work, len);

	// fclose(fw);		// Disused as of v19
	return 0;
}

int processNonce(unsigned int gnonce)
{
	// Check nonce against stack (it will almost always match on last
	// entry, but sometimes on the one before
	int i;
	for (i=WORKSTACKLEN-1; i>0; i--)
	{
		// Now using sha256_scan() rather than external program, so need
		// to split params into three (we also concatenate them into a
		// single params[] so we don't need to rewrite code)
		// NB init to 0 as we use strcat()
		char params1[16] = { 0 };
		char params2[68] = { 0 };
		char params3[WORKLEN*2-64+4] = { 0 };

		sprintf(params1,"0x%08x", gnonce);

		int j;
		for (j=0; j<32; j++)
		{
			char byte[3] = { 0 };
			sprintf(byte,"%02x", workstack[i*WORKLEN+j]);
			strcat(params2, byte);
		}
	
		for (j=32; j<WORKLEN; j++)
		{
			char byte[3] = { 0 };
			sprintf(byte,"%02x", workstack[i*WORKLEN+j]);
			strcat(params3, byte);
		}
	
		// sprintf(command,"./sha256_generic %s", params);
		// printf("system %s\n",command); fflush(stdout);
		// int res = system(command);

		printf("\n");	// Previous line (IN [nn] ...) was not terminated

		int res = sha256_scan(params1, params2, params3);

		printf("sha256 %s\n", res ? "BAD HASH" : "MATCH"); fflush(stdout);
		if (res==0)
		{
			// That was a MATCH so submit to JSON
			// Fudge so we don't have to rewrite code to use params1,2,3
			char params[WORKLEN*2+20];
			char command[WORKLEN*2+512];// NB a long url will break this
										// so TODO malloc instead

			sprintf(params,"%s %s %s", params1, params2, params3);

			// Reverse nonce (inefficiently, fix later)
			char rev[8];
			memcpy(rev+0, params+8, 2);
			memcpy(rev+2, params+6, 2);
			memcpy(rev+4, params+4, 2);
			memcpy(rev+6, params+2, 2);
			// Insert nonce
			// printf("pre--insert=<%s>\n", params);
			memcpy(params+228, rev, 8);
			// printf("post-insert=<%s>\n", params);

			time_t now;
			time(&now);
			char tmpfile[256];
			sprintf(tmpfile,"%s/hash_%u",minetmp,now);
			// NB run the submission in the background, so as not to hang
			sprintf(command,"./send_json %s %s %s >>%s 2>&1&", url, passwd, params+76, tmpfile);
			// This is useful so leave it in...
			printf("system %s\n",command); fflush(stdout);
			int res = system(command);
			printf("send_json res=%d\n", res); fflush(stdout);
			return 0;	// Else we submit in triplicate!
		}
	}
	
	printf("WARNING nonce did NOT hash correctly, NOT submitted\n"); fflush(stdout);
	gn_count--;	// Don't include it in the running total
	return 0;
}

main(int Parm_Count, char *Parms[])
{
   char instr[] = "Command line parameters in the following order (ALL required):\r\n";
   char instr1[] ="1.  The device name      Ex: /dev/ttyAMA0\n";
   char instr2[] ="2.  Baud Rate            Ex: 4800 \n";
   char instr3[] ="3.  Number of Data Bits  Ex: 8 \n";
   char instr4[] ="4.  Number of Stop Bits  Ex: 0 or 1\n";
   char instr5[] ="5.  Parity               Ex: 0=none, 1=odd, 2=even\n";
   char instr6[] ="6.  Configuration file   Ex: config.txt\n";

   char instr7[] ="Example: ./mine /dev/ttyAMA0 4800 8 0 0 config.txt\n";

   char Param_strings[7][80];
   char message[90];

   int fd, c, res, i, error;
   char In1, Key;
   struct termios oldtio, newtio;       //place for old and new port settings for serial port
   struct termios oldkey, newkey;       //place tor old and new port settings for keyboard teletype
   struct sigaction saio;               //definition of signal action
   char buf[255];                       //buffer for where data is put
   
   error=0;
   //read the parameters from the command line
   if (Parm_Count==7)  //if there are the right number of parameters on the command line
   {
      for (i=1; i<Parm_Count; i++)  // for all wild search parameters
      {
         strcpy(Param_strings[i-1],Parms[i]);
      }
      i=sscanf(Param_strings[0],"%s",devicename);
      if (i != 1) error=1;
      i=sscanf(Param_strings[1],"%li",&Baud_Rate);
      if (i != 1) error=1;
      i=sscanf(Param_strings[2],"%i",&Data_Bits);
      if (i != 1) error=1;
      i=sscanf(Param_strings[3],"%i",&Stop_Bits);
      if (i != 1) error=1;
      i=sscanf(Param_strings[4],"%i",&Parity);
      if (i != 1) error=1;
      // i=sscanf(Param_strings[5],"%i",&Format);	// MJ Now use directly
      // if (i != 1) error=1;
	  configFile = Param_strings[5];				// NB copies address
      sprintf(message,"Device=%s, Baud=%li\r\n",devicename, Baud_Rate); //output the received setup parameters
      fputs(message,stdout);
      sprintf(message,"Data Bits=%i  Stop Bits=%i  Parity=%i  Config=%s\r\n",Data_Bits, Stop_Bits, Parity, configFile);
      fputs(message,stdout);
   }  //end of if param_count==7

   if ((Parm_Count==7) && (error==0))  //if the command line entrys were correct
   {                                    //run the program
      switch (Baud_Rate)
      {
         case 38400:
         default:
            BAUD = B38400;
            break;
         case 19200:
            BAUD  = B19200;
            break;
         case 9600:
            BAUD  = B9600;
            break;
         case 4800:
            BAUD  = B4800;
            break;
         case 2400:
            BAUD  = B2400;
            break;
         case 1800:
            BAUD  = B1800;
            break;
         case 1200:
            BAUD  = B1200;
            break;
         case 600:
            BAUD  = B600;
            break;
         case 300:
            BAUD  = B300;
            break;
         case 200:
            BAUD  = B200;
            break;
         case 150:
            BAUD  = B150;
            break;
         case 134:
            BAUD  = B134;
            break;
         case 110:
            BAUD  = B110;
            break;
         case 75:
            BAUD  = B75;
            break;
         case 50:
            BAUD  = B50;
            break;
      }  //end of switch baud_rate
      switch (Data_Bits)
      {
         case 8:
         default:
            DATABITS = CS8;
            break;
         case 7:
            DATABITS = CS7;
            break;
         case 6:
            DATABITS = CS6;
            break;
         case 5:
            DATABITS = CS5;
            break;
      }  //end of switch data_bits
      switch (Stop_Bits)
      {
         case 1:
         default:
            STOPBITS = 0;
            break;
         case 2:
            STOPBITS = CSTOPB;
            break;
      }  //end of switch stop bits
      switch (Parity)
      {
         case 0:
         default:                       //none
            PARITYON = 0;
            PARITY = 0;
            break;
         case 1:                        //odd
            PARITYON = PARENB;
            PARITY = PARODD;
            break;
         case 2:                        //even
            PARITYON = PARENB;
            PARITY = 0;
            break;
      }  //end of switch parity
       
      //open the device(com port) to be non-blocking (read will return immediately)
      fd = open(devicename, O_RDWR | O_NOCTTY | O_NONBLOCK);
      if (fd < 0)
      {
         perror(devicename);
         exit(-1);
      }

      //install the serial handler before making the device asynchronous
      saio.sa_handler = signal_handler_IO;
      sigemptyset(&saio.sa_mask);   //saio.sa_mask = 0;
      saio.sa_flags = 0;
      saio.sa_restorer = NULL;
      sigaction(SIGIO,&saio,NULL);

      // allow the process to receive SIGIO
      fcntl(fd, F_SETOWN, getpid());
      // Make the file descriptor asynchronous (the manual page says only
      // O_APPEND and O_NONBLOCK, will work with F_SETFL...)
      fcntl(fd, F_SETFL, FASYNC);

      tcgetattr(fd,&oldtio); // save current port settings 
      // set new port settings for canonical input processing 
      newtio.c_cflag = BAUD | CRTSCTS | DATABITS | STOPBITS | PARITYON | PARITY | CLOCAL | CREAD;
      newtio.c_iflag = IGNPAR;
      newtio.c_oflag = 0;
      newtio.c_lflag = 0;       //ICANON;
      newtio.c_cc[VMIN]=1;
      newtio.c_cc[VTIME]=0;
      tcflush(fd, TCIFLUSH);
      tcsetattr(fd,TCSANOW,&newtio);

		// MJ Starts here ...
		if (!configFile)
		{
			printf("Error no configuration file supplied, exiting\n");
			return 1;
		}

		if (read_config(configFile))
		{
			printf("Error parsing config file %s, exiting\n", configFile);
			return 1;
		}
		if (!url || !*url || !passwd || !*passwd)	// Belt'n'Braces check
		{
			printf("Internal error - no url/passwd\n");
			return 1;
		}

		// Convert passwd from plain text "username:password" to base64

		// printf("passwd IN  = <%s>\n", passwd);
		size_t passwd_enc_len;
		char *passwd_enc = base64_encode(passwd, strlen(passwd), &passwd_enc_len);
		// printf("passwd OUT = <%s> len %d\n", passwd_enc, passwd_enc_len);
		free(passwd);
		passwd = passwd_enc;

		printf("URL = %s    <<<<<<<=======\n", url);	// So we know if LIVE or TEST
		// return(0);	// For DEBUG of url selection

		int ret = mkdir(minetmp, 0755);	// NB Octal permissions
		if (ret && errno != EEXIST)
		{
			printf("Could not create directory %s, error %d\n", minetmp, errno);
			return 1;
		}

		uint64_t tick=0;		// NB 64 bit else wraps in ~ 4000 sec
		uint64_t hashtick=0;	// Record tick last hash received for resync
		int sendcount=0;
		while (STOP==FALSE)
		{
		usleep(1000);		// Sleep a millisecond
		tick++;
		if ((tick%20000)==1)	// Every 20 secs, starting immediately
		{
			getwork();		// This now simply sends request
		}

		if (*workreq_file)
		{
			if (!checkwork())
			{
				int err=0;
				if ((err=loadwork()))
				{
					fprintf(stdout, "\nloadwork() returned ERROR %d\n", err);
				}
				else
				{
					status = 1;
					sendcount = 0;
					fprintf(stdout, "GOLD %d sending work ", gn_count);	// NB no \n
				}
			}
			fflush(stdout);
		}

		if (status==1)  // Sending work
		{
			// Verbose (comment out to disable)
			// printf("%02x",sendwork[sendcount]);
			// fflush(stdout);

			write(fd,&sendwork[sendcount++],1);  //write 1 byte to the port
			usleep(1000);		// Sleep another millisecond
			// 2ms sleep per byte keeps us well within 9600 baud
			if (sendcount >= WORKSEND)
			{
				status = 0;
				sendcount = 0;
				fprintf(stdout, " ...done\n");
				fflush(stdout);
			}
         }

		// Reset gnonceBytes if its too long since last hash (this will
		// resync input, and is needed if running TWO DE0-Nano's with
		// the serial_solo/mine ... it works proviced nonce's are widley
		// separated since both cards have same work!
		if (gnonceBytes && (tick - hashtick > 100))	// 100ms
		{
			gnonceBytes = 0;
			printf("RESET gnonceBytes %d at %lld - %lld\n",
				gnonceBytes, tick, hashtick);
		}

		// after receiving SIGIO, wait_flag = FALSE, input is available and
		// can be read ... MJ This does NOT work ... read() blocks, so replace
		// it with a select

		int				max_fd;
		fd_set			input;
		struct timeval	timeout;

		/* Initialize the input set */
		FD_ZERO(&input);
		FD_SET(fd, &input);

		max_fd = fd + 1;

		/* Initialize the timeout structure */
		timeout.tv_sec  = 0;
		timeout.tv_usec = 100;

		/* Do the select */
		int n = select(max_fd, &input, NULL, NULL, &timeout);

		/* See if there was an error */
		if (n < 0)
			perror("select failed");
		else if (n == 0)
		{
			 // printf("TIMEOUT"); fflush(stdout);
		}
		else
		{
    		/* We have input - v23 changed logging tag to GN (was IN) */
			printf(" GN "); fflush(stdout);
			if (FD_ISSET(fd, &input))
			{
				res = read(fd,buf,255);
				if (res>0)
				{
					for (i=0; i<res; i++)  //for all chars in string
					{
						In1 = buf[i];
						fprintf(stdout,"[%02x] ",In1);
						fflush(stdout);

						// CARE quick and dirty - TODO resync
						hashtick = tick;	// v22 OOPS I forgot this in v21
						gnonce <<= 8;
						gnonce |= In1;
						if (++gnonceBytes == 4)
						{
							gn_count++;		// v22 moved this
							processNonce(gnonce);
							gnonceBytes = 0;
						}

					} // end of for all chars in string
				}  // end if res>0
				wait_flag = TRUE;      /* wait for new input */
			} // end if (FD_ISSET(fd, &input))
		}
      }  // while stop==FALSE

      // restore old port settings
      tcsetattr(fd,TCSANOW,&oldtio);
      close(fd);        //close the com port
   }  //end if command line entrys were correct
   else  //give instructions on how to use the command line
   {
      fputs(instr,stdout);
      fputs(instr1,stdout);
      fputs(instr2,stdout);
      fputs(instr3,stdout);
      fputs(instr4,stdout);
      fputs(instr5,stdout);
      fputs(instr6,stdout);
      fputs(instr7,stdout);
   }
}  //end of main

/***************************************************************************
* signal handler. sets wait_flag to FALSE, to indicate above loop that     *
* characters have been received.                                           *
***************************************************************************/

void signal_handler_IO (int status)
{
//    printf("received SIGIO signal.\n");
   wait_flag = FALSE;
}
