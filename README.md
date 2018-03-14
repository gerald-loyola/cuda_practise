# cuda_practise
gpu parallel computing using cuda api

Three kernels were used for this bingo card daub simulation. 
 1. Loading 32 numbers called for each game room(for eg. if 1k rooms simulated then total 32k numbers loaded). 
 2. Loading 256(5x5) cards per room. 
 3. Daubing above cards(256 x 1000) based on the 32 numbers from a game room. 