// send-json.c based on web-win.c from fpga\mining\spoof on laptop
//
// Previous comments ...
// REPURPOSE THIS to send a POST request to spoofcoin.pl for debugging
// Usage: web-win localhost 8332 /
//
// web-win.c - investigate basic web client
// Back on Ubuntu, add the #ifdef's to make it compile on both (I hope)
//
// WINDOWS version of ubuntu program...
// vcvars
// cl web-win.c ws2_32.lib	// lib needed for WinSock2 (see SDK)
// Needed quite a bit of work to get it to run without errors or crashing, vis:
// Call WSAStartup() before using sockets
// Call send() instead of write() - else CRASH
// Call recv() instead of read() - else CRASH
// Call shutdown() then closesocket() instead of close() - else CRASH
// Call WSACleanup() once finished (though no harm is done if just exit).
//
// Ubuntu: Compiles fine with just "make web" - no makefile needed
//
// Based on client.c from http://www.linuxhowtos.org/C_C++/socket.htm
// Test with UsbWebserver - NB the initial slash on file is required...
//   ./web-win 10.0.2.2 80 /file

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

#ifndef _WIN32
#include <unistd.h> // NOT WINDOWS
#include <sys/socket.h> // NOT WINDOWS
#include <netinet/in.h>
#include <netdb.h> 

#define INVALID_SOCKET -1
int WSAGetLastError () {return 123454321;} // ARBITARY
#endif

#ifdef _WIN32
// Hmmm, either will do, not both (barfs), however windows.h does not include SD_BOTH (value=2)
// So use winsock.h 
// #include <windows.h>
#include <winsock2.h>

#define bzero ZeroMemory	// Since not on windows
// #define bcopy memcpy		// Since not on windows - OOPS NO, src,dst are the wrong way round
//                               ... instead use memcpy() directly and swap src,dst
#endif


int getwork=0;		// JSON MODE
int submit_nonce=0;	// JSON MODE

void error(const char *msg)
{
    perror(msg);
    exit(0);
}

int main(int argc, char *argv[])
{
    int sockfd, portno, n;
    struct sockaddr_in serv_addr;
    struct hostent *server;

#ifdef _WIN32
// NB Default cl.exe requires these to be at top (else gives obscure type error)
// AHA Compiling a .c file is stricter than .cpp ... eg .c will give obscure type errors if you declare
// variables anywhere except at the top of a function. Use /Tp to override and compile .c as .cpp though
// might as well just rename the file .cpp

    WSADATA wsaData;		// NB Default cl.exe requires these to be at top (else gives obscure type errors)
    int wVersionRequested;
    int err;
#endif

    char buffer[8192];		// Made these MUCH larger for json_send
    char buftmp[8192];

    if (argc  != 6) {
       fprintf(stderr,"usage %s hostname port file passwd JSON_PARAMETER\n", argv[0]);
       exit(0);
    }

	// We require a JSON_PARMETER, vis "getwork" or submit nonce
	// printf("argv[5]=%s\n", argv[5]);
	if (!strcmp(argv[5],"getwork"))
	{
		getwork=1;
	}
	else if (strlen(argv[5])==256)
	{
		submit_nonce = 1;
	}
	else
	{
		fprintf(stderr,"usage %s was expecting JSON_PARAMETERS=\"getwork\" or data[256], len=%d\n", argv[0], strlen(argv[5]));
		 exit(0);
	}

    portno = atoi(argv[2]);

#ifdef _WIN32
    // WINDOWS NEEDS THIS...
    wVersionRequested = MAKEWORD( 2, 2 );
    err = WSAStartup( wVersionRequested, &wsaData ); // TODO check err to see if it worked
#endif

    sockfd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (sockfd == INVALID_SOCKET)
    {
        // Error 10093 - WASNOTINITIALISED means need to call WSAStartup()
        fprintf(stderr,"ERROR opening socket error=%d", WSAGetLastError());
        exit(0);
    }
    server = gethostbyname(argv[1]);
    if (server == NULL) {
        fprintf(stderr,"ERROR, no such host: <%s>\n",argv[1]);
        exit(0);
    }
    bzero((char *) &serv_addr, sizeof(serv_addr));
    serv_addr.sin_family = AF_INET;

    // NB bcopy() has reversed args cf memcpy() so fix..
#ifdef _WIN32
    memcpy((char *)&serv_addr.sin_addr.s_addr,
         (char *)server->h_addr, 
         server->h_length);
    serv_addr.sin_port = htons(portno);
#else
    bcopy((char *)server->h_addr, 
          (char *)&serv_addr.sin_addr.s_addr,
         server->h_length);
#endif
    serv_addr.sin_port = htons(portno);
    if (connect(sockfd,(struct sockaddr *) &serv_addr,sizeof(serv_addr)) < 0)
    {
        // Error 10049 - WSAEADDRNOTAVAIL means bind adress was invalid
        // AHA I was using memcpy() for bcopy() above, with reversed args
        fprintf(stderr,"ERROR connecting error=%d", WSAGetLastError());
        exit(0);
    }

    // Setup request
    bzero(buffer,sizeof(buffer));
    bzero(buftmp,sizeof(buffer));

	sprintf(buffer,"POST %s HTTP/1.1\r\nAccept: */*\r\nHost: %s:8332\r\nUser-Agent: kramble fpgaminer pi client package 1.0\r\nAuthorization: Basic %s\r\n",argv[3],argv[1],argv[4]);
	
	if (getwork)
	{
		// MJ 25/3/2013 removed ttrailing " =" since it breaks stratum proxy
		// strcat(buftmp,"{\"method\": \"getwork\", \"params\": [], \"id\":0} =");
		strcat(buftmp,"{\"method\": \"getwork\", \"params\": [], \"id\":0}");
		char contentType[128];
		// NB Be sure to set correct length else server will hang
		sprintf(contentType,"Content-Type: application/json\r\nContent-Length: %d\r\n\r\n", strlen(buftmp));
		strcat(buffer,contentType);
		strcat(buffer,buftmp);
	}
	else if (submit_nonce)
	{
		// This is a typical nonce submission ...
		// strcat(buftmp,"{\"method\": \"getwork\", \"params\": [ \"000000015c972bf2cc9286be39638ae8713f12c38b97cd5d011b26c7000001b9000000004feabf3938ae810cfa717653551322e180e5efa5b2fed72c127c422acbd25faa508e4e7c1a0575ef0dd9580a000000800000000000000000000000000000000000000000000000000000000000000000000000000000000080020000\" ], \"id\":1} =");
		char str[1024];
		// MJ 25/3/2013 removed ttrailing " =" since it breaks stratum proxy
		// sprintf(str,"{\"method\": \"getwork\", \"params\": [ \"%s\" ], \"id\":1} =", argv[5]);
		sprintf(str,"{\"method\": \"getwork\", \"params\": [ \"%s\" ], \"id\":1}", argv[5]);
		strcat(buftmp, str);
		char contentType[128];
		// NB Be sure to set correct length else server will hang
		sprintf(contentType,"Content-Type: application/json\r\nContent-Length: %d\r\n\r\n", strlen(buftmp));
		strcat(buffer,contentType);
		strcat(buffer,buftmp);
		printf("SENDING <%s>\n", buffer);	// For DEBUG
	}
	else
	{
		fprintf(stderr, "%s INTERNAL ERROR: not getwork or submit_nonce\n");
		exit(1);
	}

	// printf("Writing to socket...<%s>\n",buffer); fflush(stdout);

    // n = write(sockfd,buffer,strlen(buffer)); // CRASHES IN WINDOWS
    n = send(sockfd,buffer,strlen(buffer),0); // OK
    if (n < 0) 
         error("ERROR writing to socket");

    // MJ made this a loop..
    // NB only exits after server timout (5 seconds by default, http.conf
    //    setting KeepAliveTimeout)
	// BUT stratum proxy does NOT time out!! Need to use select/poll
	int selectcount = 0;
    do
    {
	   // Wait for data
        int             max_fd;
        fd_set          input;
        struct timeval  timeout;

        /* Initialize the input set */
        FD_ZERO(&input);
        FD_SET(sockfd, &input);

        max_fd = sockfd + 1;

        /* Initialize the timeout structure */
        timeout.tv_sec  = 0;
        timeout.tv_usec = 10000;	// 10 millisec

        /* Do the select */
        int n = select(max_fd, &input, NULL, NULL, &timeout);

        /* See if there was an error */
        if (n < 0)
		{
            perror("select failed");
			break;
		}
        else if (n == 0)
		{
             // printf("TIMEOUT\n"); fflush(stdout);
			 selectcount++;
			 if (selectcount > 2000)	// 20 secs assuming 10mS timeout
             {
				// NB This print goes to output in /tmp/fpgaminer/work_nnnn
				// which is not what we really want but it does no harm and
				// is useful debug info so leave it in for now.
				printf("Closing connection after 20 secs\n"); fflush(stdout);
				break;
			 }
			continue;
        }
        else
        {
            if (!FD_ISSET(sockfd, &input))
				continue;	// Its actually an error!!
			// else fallthrough to recv ...
		}

       bzero(buffer,256);
       // n = read(sockfd,buffer,255);	// CRASHES IN WINDOWS
       n = recv(sockfd,buffer,255,0);	// OK
       if (n < 0)
         error("ERROR reading from socket");
       else
    	   printf("%s",buffer);	// NB Remove \n - not wanted
	fflush(stdout);
    } while (n > 0);

    printf("\n");

    // close(sockfd);	CRASHES IN WINDOWS, instead do these...
#ifdef _WIN32
    shutdown(sockfd,SD_BOTH);	// Optional - NB see unix sockets FAQ
    // shutdown() indicates that the socket will no longer be used for..
    // READ, WRITE or BOTH cf. close/closesocket which just closes the handle
    // which still allows duplicate handles in other treads/processes to
    // be used as normal. So shutdown() is actually more significant.
    // This only applies for multi-thread/process socket usage - take CARE.
    closesocket(sockfd);
#else
    shutdown(sockfd,SHUT_RDWR);	// Optional
    close(sockfd);		// Unix does not have closesocket()
#endif
#ifdef _WIN32
    WSACleanup();
#endif
    return 0;
}

