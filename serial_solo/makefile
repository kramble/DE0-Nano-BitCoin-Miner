CC     = gcc
CFLAGS = -g

all: mine

mine: mine.o base64.o sha256.o
# Commands start with TAB not spaces
	$(CC) $(LDFLAGS) -o $@ $^
	rm mine.o base64.o sha256.o

mine.o: mine.c
	$(CC) $(CFLAGS) -c -o $@ $<

base64.o: base64.c
	$(CC) $(CFLAGS) -c -o $@ $<

sha256.o: sha256.c
	$(CC) $(CFLAGS) -c -o $@ $<
