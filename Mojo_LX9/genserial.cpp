// genserial.cpp - create test vectors

#include "stdio.h"
#include "stdlib.h"
#include "string.h"
#include "ctype.h"

char data[] = "85a24391639705f42f64b3b688df3d147445123c323e62143d87e1908b3f07efc513051a02a99050bfec0373";

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