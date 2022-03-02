data{
  // training datalist, historical observations 
  int<lower=0> N;                       // # observations total 
  int<lower=0, upper=1> S[N];           // success
  int<lower=0> K;                       // # of fixed effects
  matrix[N,K] X;                        // fixed effects matrix   
  int<lower=0> J;                       // # of group level effects
  row_vector[J] Z[N];                   // group level effects matrix
  int<lower=0> G;                       // groups
  int<lower=0> g[N];                    // group id

  // holdout data
  int<lower=0> hold_N;                  // hold_N == 2 if no held out data
  int<lower=0, upper=1> hold_S[hold_N];
  matrix[hold_N,K] hold_X;
  row_vector[J] hold_Z[hold_N];
  int<lower=0> hold_G;
  int<lower=0> hold_g[hold_N];
  
  // For generating IBM predictions use all data 
  int<lower=0, upper=1> IBM;          // Flag if predictions for IBM are to be generated 
  int<lower=0> IBM_N;                  
  matrix[IBM_N,K] IBM_X;
  row_vector[J] IBM_Z[IBM_N];
  int<lower=0> IBM_G;
  int<lower=0> IBM_g[IBM_N];
}
transformed data{ 
  vector[J] alpha;                          // prior on dirichlet distribution

  for(i in 1:J)
    alpha[i] = 1; 
}
parameters{
  // for training data model  
	vector[K] beta;                       // fixed effects
	simplex[J] pi_;                       // simplex for diagonal of group-level covariance matrix 
	real<lower=0> tau;                    // scale parameter for group-level covariance matrix
  cholesky_factor_corr[J] L_u;          // cholesky factor for group-level correlation
	matrix[J,G] u_raw;                    // raw group-level effects 
}
transformed parameters{
  vector[N] mu;             
  vector[J] u[G]; // un-scaled group effects 
  matrix[J,J] Sigma_L = diag_pre_multiply(pi_*J*tau^2, L_u);  // cholesky of covariance 
  
  {
    vector[N] fixef = X*beta;     // fixed effects 

    for(j in 1:G)
      u[j] = Sigma_L * col(u_raw, j);    

    for(n in 1:N)
      mu[n] = fixef[n] + Z[n]*u[g[n]];
  }
  
}
model{
  // Priors
  beta ~ normal(0, 5);
  pi_ ~ dirichlet(alpha);       // dirichlet as per rstanarm glmer vignette
  tau ~ gamma(1,1);             // gamma as per rstanarm glmer vignette
  L_u ~ lkj_corr_cholesky(1.0);
  to_vector(u_raw) ~ std_normal();

  // Likelihood
  S ~ bernoulli_logit_lpmf(mu);
}
generated quantities {
  real log_lik[N]; 
  vector[hold_N] hold_mu;         
  vector[hold_N] hold_log_lik;
  real hold_SSE; 
  vector[IBM_N] IBM_mu;           
  
  for(i in 1:N)
    log_lik[i] = bernoulli_logit_lpmf(S[i] | mu[i]);
  
  {
    // Generate out of sample predictions and log-likelihoods 
    vector[J] hold_u[hold_G];       
    vector[hold_N] hold_fixef = hold_X*beta; 
    vector[hold_G*J] ones = rep_vector(1.0, hold_G*J); 
    vector[hold_G*J] zeros = rep_vector(0.0, hold_G*J); 
    matrix[J, hold_G] hold_u_raw = to_matrix( normal_rng(zeros, ones), J, hold_G); 
    vector[hold_N] hold_SE; 

    for(i in 1:hold_G)
      hold_u[i] = Sigma_L * col(hold_u_raw, i);
      
    for(i in 1:hold_N)
      hold_mu[i] = hold_fixef[i] + hold_Z[i]*hold_u[hold_g[i]];
    
    for(i in 1:hold_N){ 
      hold_log_lik[i] = bernoulli_logit_lpmf(hold_S[i] | hold_mu[i]);
      hold_SE[i] = ( hold_mu[i] - hold_S[i] )^2 ;
    }
    
    hold_SSE = sum(hold_SE);
  }

  if( IBM ==  1 ){ 
    vector[J] IBM_u[IBM_G];       
    vector[IBM_N] IBM_fixef = IBM_X*beta; 
    vector[IBM_G*J] ones = rep_vector(1.0, IBM_G*J); 
    vector[IBM_G*J] zeros = rep_vector(0.0, IBM_G*J); 
    matrix[J, IBM_G] IBM_u_raw = to_matrix( normal_rng(zeros,ones), J, IBM_G); 
  
    for(i in 1:IBM_G)
      IBM_u[i] = Sigma_L * col(IBM_u_raw, i);
      
    for(i in 1:IBM_N)
      IBM_mu[i] = IBM_fixef[i] + IBM_Z[i]*IBM_u[IBM_g[i]];
      
  }else{
    
    IBM_mu = to_vector(rep_array(0, IBM_N));
  }
}
