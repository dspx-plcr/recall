.c.o:
	$(CC) -g -o $@ -c $< -I/usr/local/include
recall: main.o
	$(CC) -o $@ main.o -L/usr/local/lib -lreadline -lsqlite3 -lm
