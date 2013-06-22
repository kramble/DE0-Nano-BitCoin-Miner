//  prog_both.c monitors BOTH altera and xilinx

//  prog_fpga.c - program EP4CE10 fpga via gpio pins (see README_MJ)
//  NB needs to run continuously as it monitors config_done and
//  reprograms as neccessary so need to run this as:
//  sudo nohup ./prog_fpga >/log/prog_fpga 2?&1 &
//
//  BASED ON ...
//  How to access GPIO registers from C-code on the Raspberry-Pi
//  Example program
//  15-January-2012
//  Dom and Gert
//  Revised: 01-01-2013

/*
README ...
Based on gpio_example.c (downloaded from elinux.org/Rpi_Low-Level_peripherals)

NB The example used gpio_7 to gpio_11 which are located on the bottom end
of p1 connector on pins p1-19 through p1-26
NB gnd is at p1-20 and p1-25 and the order is a bit mixed-up vis:

P1-17 3.3V		P1-18 gpio_24
P1-19 gpio_10	P1-20 gnd
P1-21 gpio_9	p1-22 gpio_25
p1-23 gpio_11	p1-24 gpio_8
p1-25 gnd		p1-26 gpio_7

These gpio's are unassigned at reset, so can be used without reconiguring.

So I will use ...
gpio_10 output nConfig (TMS in jtag version)
gpio_9  output dck (TCK in jtag version)
gpio_11 output data (TDI in jtag version)
gpio_8  ouput  nPROG (xilinx)
gpio_7  input  conf_done (altera)
gpio_25 input  conf_done (xilinx)

I couldn't get it to work connecting via resistors, or via level shifting
transistors, however using 74CH244 (like byteblaster) DID work.
100 ohm resistors on inputs (from pi), outputs driving directly to fpga
and 10 (ten) ohm resistor connecting fpga and pi ground.

JTAG did not work (it returns correct ID but programming fails), however
serial programming WORKS for BOTH xilinx and altera.
UNFORTUNATELY the rbf formats are MSB first and LSB first respectively,
so I have different programs for each. I also took the oportunity
to use different pins for nCOnfig/nPROG so no need to swap wiring (the clock
and data remain connected in parallel). Only the altera device has conf_done
connected back to pi (gpio 7) so only this one impliments automatic
reprogramming.

*/

#define DEFAULT_RBF_FILENAME_A "EP4CE10.rbf"
#define DEFAULT_RBF_FILENAME_X "lx9.rbf"

// Access from ARM Running Linux

#define BCM2708_PERI_BASE        0x20000000
#define GPIO_BASE                (BCM2708_PERI_BASE + 0x200000) /* GPIO controller */


#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <time.h>
#include <errno.h>

#define PAGE_SIZE (4*1024)
#define BLOCK_SIZE (4*1024)

int  mem_fd;
char *gpio_map;
char *rbf_filename;
char *rbf_filename_a;
char *rbf_filename_x;
int force_a=0;
int force_x=0;

// I/O access
volatile unsigned *gpio;

// GPIO setup macros. Always use INP_GPIO(x) before using OUT_GPIO(x) or SET_GPIO_ALT(x,y)
#define INP_GPIO(g) *(gpio+((g)/10)) &= ~(7<<(((g)%10)*3))
#define OUT_GPIO(g) *(gpio+((g)/10)) |=  (1<<(((g)%10)*3))
#define SET_GPIO_ALT(g,a) *(gpio+(((g)/10))) |= (((a)<=3?(a)+4:(a)==4?3:2)<<(((g)%10)*3))

#define GPIO_SET *(gpio+7)  // sets   bits which are 1 ignores bits which are 0
#define GPIO_CLR *(gpio+10) // clears bits which are 1 ignores bits which are 0

void setup_io();

int read_gpio(int pin)
{
	// Based on wiringPi.c
	// Offset to read register is (gpio+13)
	unsigned int val = *(gpio+13);
	return (val & (1<<pin)) ? 1 : 0;
}

void print_time()
{
	time_t rawtime;
	struct tm * timeinfo;

	time (&rawtime);
	timeinfo = (struct tm*)localtime (&rawtime);
	char *s = asctime(timeinfo);
	int len = strlen(s);
	if (len)
		s[len-1] = 0;	// Strip last char (ie \n)

	printf ("%s", s);
}

// Macros for pin numbers (see README_MJ)
#define CONFIG_DONE_A 7
#define CONFIG_DONE_X 25
// Altera uses pin 10 cf 8 for xilinx
#define NCONFIG_X 8
#define NCONFIG_A 10
#define DCLK 9
#define DATA 11 

int OLD_my_usleep(int usec)
{
	// CRUDE Wrapper around nanosleep (does not support usec > 999999)
	struct timespec req, rem;
	req.tv_sec = 0;
	req.tv_nsec = usec*1000;
	rem.tv_sec = 0;
	rem.tv_nsec = 0;
	int rv = -1;	// Must be non zero else loop never runs
	while (rv)
	{
		rv = nanosleep(&req,&rem);
		if (rv)
		{
			if (errno != EINTR)
				break;
			// Interrupted so copy remainder and call again
			req.tv_sec = rem.tv_sec;
			req.tv_nsec = rem.tv_nsec;
		}
	}
	return rv;	// Returns 0 for success, or -1 with error in errno
}

int my_usleep(int n)
{
	// Use spinwait (calibrate via testspin.c)
	// This is so VERY NOT PORTABLE !!
	while(n--)
	{
		// Use volatile to hope it will not optimise away
		volatile int i = 54;	// TWEAK for 1 microsecond
		// volatile int i = 500;	// TWEAK for SLOW
		while (i--)	;			// Spin
	}
}

void send_bit(int b)
{
	// Timing using usleep achieves approx 8000 bits/second which is
	// WAY slower than I would like so try nanosleep via my_usleep()
	// ... makes NO difference at all !! Could try the other timing
	// calls eg clock_getres(), clock_nanosleep() etc, possibly just use
	// clock_gettime() with  spinwaiting and occasional usleep() so as
	// not to hog the cpu.
	// HOWEVER I'll just live with it for now as its not taking up too
	// much CPU (28%) and sends 188K bytes (1.6Mbit) in approx 247 sec

	// Now using spinwait, NB must include a real wait to avoid hogging
	// CPU, so do one usleep per byte in caller
	// ... it programs in 19 seconds using 40% CPU, which seems OK

	// Assumes DCLK is already LOW (so initialise prior to first call)
	if (b)
			GPIO_SET = 1<<DATA;
	else
			GPIO_CLR = 1<<DATA;
	my_usleep(1);			// Setup time DATA->DCLK
	GPIO_SET = 1<<DCLK;		// DCLK HIGH
	my_usleep(1);			// DCLK high period
	GPIO_CLR = 1<<DCLK;		// DCLK LOW
	// NO usleep here as DCLK low period is done by the setup time DATA->DCLK
	// After last bit has been sent DCLK is LOW and DATA is as per final bit
}

void prog_fpga()
{
	usleep(1000);			// Let it settle

	int dotcount = 0;
	int first = 1;
	for(;;)	// Main loop never exits (kill process to stop)
	{
		fflush(stdout);
		if (first)
		{
			if (!force_a && read_gpio(CONFIG_DONE_A) &&
				!force_x && read_gpio(CONFIG_DONE_X))
			{
				printf("FPGA already configured, entering check loop (use -fa/-fx to force)\n");
			}
			first = 0;
		}
		else
		{
			printf(".");
			if (dotcount++ > 59)
			{
				dotcount=0;
				printf("\n");
			}
			sleep(10);		// Only check every few seconds
		}

		// Loop until CONFIG_DONE goes low (fpga lost programming)
		if (!force_a && read_gpio(CONFIG_DONE_A) &&
			!force_x && read_gpio(CONFIG_DONE_X))
			continue;
				
		if (dotcount)
				printf("\n");

		int DO_XILINX =  0;		// Use 1 for xilinx, 0 for altera
		int MSB_first = 0;		// CONFIG 1 for xilinx, 0 for altera
		int NCONFIG = NCONFIG_A;
		rbf_filename = rbf_filename_a;

		// CARE ordering is important here ...
		if (force_a)
		{
			// Defaults as above (MUST be first in if/else clause)
		}
		else if (force_x || !read_gpio(CONFIG_DONE_X))
		{
			DO_XILINX = 1;
			MSB_first = 1;
			NCONFIG = NCONFIG_X;
			rbf_filename = rbf_filename_x;
		}
		// Else we assume CONFIG_DONE_A and we will program altera

		force_a = 0;			// So will check CONFIG_DONE on subsequent loop
		force_x = 0;

		print_time();
		printf(" CONFIG_DONE LOW starting programming %s\n",
			DO_XILINX ? "xilinx" : "altera");

		FILE *f = fopen(rbf_filename,"rb");
		if (!f)
		{
			printf("ERROR opening RBF file %s, ABORTING\n", rbf_filename);
			return;
		}

		fflush(stdout);

		// Initialise NCONFIG, DCLK, DATA
		GPIO_CLR = 1<<DATA;
		GPIO_CLR = 1<<DCLK;
		GPIO_CLR = 1<<NCONFIG;	// Assert NCONFIG (active low)

		usleep(10);				// Wait 10uS
		GPIO_SET = 1<<NCONFIG;	// Release NCONFIG

		int ch;
		int count = 0;
		time_t start_time;
		time(&start_time);
		while ((ch=getc(f))!=EOF)
		{
			count++;
			int i;
			for (i=0; i<8; i++)
			{
				if (MSB_first)
				{
					// Send data MSB first (xilinx)
					send_bit((ch&0x80)>>7);
					ch<<=1;
				}
				else
				{
					// Send data LSB first (altera)
					send_bit(ch&1);
					ch>>=1;
				}
			}
			usleep(1);	// Include a real wait since spinwating in send_bit
		}
		time_t end_time;
		time(&end_time);
		printf("%d bytes sent in %d seconds\n", count, end_time-start_time);
		fflush(stdout);

		fclose(f);

		sleep(1);
		if ((DO_XILINX && read_gpio(CONFIG_DONE_X)) ||
		   (!DO_XILINX && read_gpio(CONFIG_DONE_A)))
		{
			printf("Programming SUCCESSFUL (CTRL-C to exit loop)\n");
			// TODO may want to add a check whether fpga repeatedly programs
			// OK then loses it soon afterwards (so as not to keep retrying
			// at short intervals and hogging the cpu)
		}
		else
		{
			// Wait some period to avoid hogging cpu
			int retry_secs = 300;
			printf("Programming FAILED, retry in %d secs\n",retry_secs);
			fflush(stdout);
			sleep(retry_secs);
		}
	}
}

int main(int argc, char **argv)
{
  int g,rep;
  int skiparg=0;

  if (argc>=2)	// Quick'n'Dirty arg handling
  {
	if (!strcmp(argv[1],"-fa"))
    {
		force_a=1;	// global
		argc--;
		skiparg++;
	}
	if (!strcmp(argv[1],"-fx"))
    {
		force_x=1;	// global
		argc--;
		skiparg++;
	}
  }

  // TODO fix this for prog_both (currently just does altera)
  if (argc==2)
  {
	rbf_filename_a = argv[1+skiparg];
	rbf_filename_x = DEFAULT_RBF_FILENAME_X;
    printf("Using rbf file %s\n", rbf_filename_a);
  }
  else
  {
	rbf_filename_a = DEFAULT_RBF_FILENAME_A;
	rbf_filename_x = DEFAULT_RBF_FILENAME_X;
    printf("Using default rbf files %s %s\n", rbf_filename_a, rbf_filename_x);
  }

  // Set up gpi pointer for direct register access
  setup_io();

  // Uses GPIO 7 as input and 8..11 as output

  // Switch GPIO 7 to input and GPIO 8..11 to output mode

  for (g=7; g<=11; g++)
  {
    INP_GPIO(g); // must use INP_GPIO before we can use OUT_GPIO
    if (g > 7)   // leave gpio 7 as input
		OUT_GPIO(g);
  }
  INP_GPIO(25); // add gpio_25 as xlinx config_done input

  prog_fpga();

  return 0;

} // main


//
// Set up a memory regions to access GPIO
//
void setup_io()
{
   /* open /dev/mem */
   if ((mem_fd = open("/dev/mem", O_RDWR|O_SYNC) ) < 0) {
      printf("can't open /dev/mem \n");
      exit(-1);
   }

   /* mmap GPIO */
   gpio_map = (char *)mmap(
      NULL,             //Any adddress in our space will do
      BLOCK_SIZE,       //Map length
      PROT_READ|PROT_WRITE,// Enable reading & writting to mapped memory
      MAP_SHARED,       //Shared with other processes
      mem_fd,           //File to map
      GPIO_BASE         //Offset to GPIO peripheral
   );

   close(mem_fd); //No need to keep mem_fd open after mmap

   if ((long)gpio_map < 0) {
      printf("mmap error %d\n", (int)gpio_map);
      exit(-1);
   }

   // Always use volatile pointer!
   gpio = (volatile unsigned *)gpio_map;


} // setup_io
