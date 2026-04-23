# NOTICE

Nothing here is working except for pHist and sisname. Those are ready for testing outside my own lab though.

Well, not true, mrpname works for renaming and fixing up CRC's. Reading its source is required to make it work - it was never meant to be user friendly, just to get the job done.

mpnname is getting there - it does get into an endless loop on seemingly intact files, and i have no idea why. But it is a one-shot thing to catalogue whatever is available "out there", so fixing it just for the sake of two or three games is not an incentive. Really.

To compile: fpc -B -O2 -Xs -XX -vn- -Fulazutils whatever.pp
