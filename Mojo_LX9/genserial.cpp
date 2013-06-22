// genserial.cpp

#include "stdio.h"
#include "stdlib.h"
#include "string.h"
#include "ctype.h"

// Kramble protocol
// char data[] = "85a24391639705f42f64b3b688df3d147445123c323e62143d87e1908b3f07efc513051a02a99050bfec0373";

// Teknohog/Icarus protocol
// char data[] = "85a24391639705f42f64b3b688df3d147445123c323e62143d87e1908b3f07ef0000000000000000000000000000000000000000c513051a02a99050bfec0373";

//icarus block
char data[] = 
		"4679ba4ec99876bf4bfe086082b40025"
		"4df6c356451471139a3afa71e48f544a"
		"00000000000000000000000000000000"
		"0000000087320b1a1426674f2fa722ce";


void putbit(int bit)
{
	static int t=200;
	printf("if(cycle==%d)RxD<=%d;\n",t,bit);
	t+=100;
}

int main()
{
	char ch1, ch2;
	for (int i=0; i<strlen(data); i++)
	{
		ch2 = ch1;
		ch1 = toupper(data[i]);
		if (i&1)	// Every 2nd cycle
		{
			ch1 = ch1 - '0';
			if (ch1 > 9) ch1 -= 7;
			ch2 = ch2 - '0';
			if (ch2 > 9) ch2 -= 7;
			// printf("%d %d\n", ch1, ch2);
			putbit(0);
			for (int j=0; j<4; j++)
			{
				putbit(ch1&1);
				ch1>>=1;
			}
			for (int j=0; j<4; j++)
			{
				putbit(ch2&1);
				ch2>>=1;
			}
			putbit(1);
		}
	}
	return 0;
}