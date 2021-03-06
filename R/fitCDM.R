#' Fit a CDM Model
#'
#' This function fits a CDM model on the input data as it is described by the phenoSim function.
#' @param x Matrix of predictors [N x p].
#' @param z Vector of response values [N x 1].
#' @param connect The connectivity matrix for the z vector [n x 2]. Each row contains the last and next elements of the time-series. NA values indicate not connected.
#' @param nGibbs Number of MCMC itterations
#' @param nBurnin Number of burn-in itterations.
#' @param n.adapt Number of itterations for adaptive sampling
#' @param n.chains Number of MCMC chains
#' @param quiet logical value indicating whether to report the progress
#' @param calcLatentGibbs logical value indicating whether to calculate the latent states
#' @param trend time-series expected trend as -1:decreasing, +1:increasing, 0: not constrained
#' @keywords  CDM Model Fit
#' @export
#' @import rjags
#' @examples
#'
#' #Summarize CDM Model Ouput
#'
#' ssSim <- phenoSim(nSites = 2, #number of sites
#'                   nTSet = 30, #number of Time steps
#'                   beta = c(1, 2), #beta coefficients
#'                   sig = .01, #process error
#'                   tau = .1, #observation error
#'                   plotFlag = TRUE, #whether plot the data or not
#'                   miss = 0.05, #fraction of missing data
#'                   ymax = c(6, 3) #maximum of saturation trajectory
#' )
#'
#' ssOut <- fitCDM(x = ssSim$x, #predictors
#'                 nGibbs = 200,
#'                 nBurnin = 100,
#'                 z = ssSim$z,#response
#'                 connect = ssSim$connect, #connectivity of time data
#'                 quiet=TRUE)
#'
#' summ <- getGibbsSummary(ssOut, burnin = 100, sigmaPerSeason = FALSE)
#'
#' colMeans(summ$ymax)
#' colMeans(summ$betas)
#' colMeans(summ$tau)
#' colMeans(summ$sigma)
#'
fitCDM <- function(x, z, connect=NULL,
                   # HeadTail =NULL,
                   nGibbs=1000,
                   nBurnin = 1,
                   n.adapt=100,
                   n.chains=4,
                   quiet=FALSE,
                   calcLatentGibbs=FALSE,
                   trend = +1 # -1:decreasing, +1:increasing, 0: not constrained

){
  if(trend==-1)
    t <- c(1, 0, 0)
  else if(trend==0)
    t <- c(0, 1, 0)
  else if(trend==1)
    t <- c(0, 0, 1)
  else
    stop('trend should be -1:decreasing, 0: not constrained or +1:increasing')


  if(!is.null(connect)){
    Head <- which(is.na(connect[,1]))
    Tail <- which(is.na(connect[,2]))
    Body <- which(!rowSums(is.na(connect)))
    # }else if(!is.null(HeadTail)){
    # Head <- which(HeadTail[,1])
    # Tail <- which(HeadTail[,2])
    # Body <- which(!(HeadTail[,1]|HeadTail[,2]))
  }else
  {
    stop('One of connect or HeadTail arguments should be defined.')
  }

  model <- textConnection('model
                          {
                          for (i in 1:N)
                          {
                            z[i] ~ dnorm(y[i], tau2)
                          }

                          tau2 <- pow(tau, -2)
                          tau ~ dunif(0, 100)

                          for (i in connectHead)
                          {
                            y[i] ~ dnorm(0, sigma2)
                          }

                          for (i in connectBody)
                          {
                            dy[i] ~ dnorm(x[i-1,]%*%beta*(1-y[i-1]/ymax[blocks[i]]), sigma2)
                            y[i] <- y[i-1] + t[1]*min(0, dy[i]) + t[2]*dy[i] + t[3]*max(0, dy[i])
                          }

                          for (i in connectTail)
                          {
                            dy[i] ~ dnorm(x[i-1,]%*%beta*(1 - y[i-1]/ymax[blocks[i]]), sigma2)
                            y[i] <- y[i-1] + t[1]*min(0, dy[i]) + t[2]*dy[i] + t[3]*max(0, dy[i])
                          }

                          for (i in 1:nblocks)
                          {
                            ymax[i] ~ dnorm(0, .001)T(0,10000)
                          }
                          for (i in 1:p)
                          {
                            beta[i] ~ dnorm(0, .0001)
                          }

                          for (i in 1:N)
                          {
                            zpred[i] ~ dnorm(y[i], tau2)
                          }

                          sigma2 <- pow(sigma, -2)
                          sigma ~ dunif(0.01, 0.03)
                          }')

  ssModel <- jags.model(model,
                        quiet = quiet,
                        data = list('x' = x,
                                    'z' = z,
                                    't' = t,
                                    'N' = nrow(x),
                                    'p'= ncol(x),
                                    'blocks'=cumsum(is.na(connect[,1])*1),
                                    'nblocks'=sum(is.na(connect[,1])),
                                    connectHead=Head,
                                    connectBody=Body,
                                    connectTail=Tail),
                        n.chains = n.chains,
                        n.adapt = n.adapt)

  update(ssModel, nBurnin)

  ssSamples <- jags.samples(ssModel,c('y','beta', 'sigma', 'tau', 'ymax', 'zpred'), nGibbs )


  # print(ssSamples)


  ssGibbs.jags <- data.frame(beta=t(apply(ssSamples$beta, c(1,2), mean)),
                             ymax=t(apply(ssSamples$ymax, c(1,2), mean)),
                             sigma=t(apply(ssSamples$sigma, c(1,2), mean)),
                             tau=t(apply(ssSamples$tau, c(1,2), mean))
  )
  latentGibbs <- NULL
  if(calcLatentGibbs) latentGibbs <- t(apply(ssSamples$y, c(1,2), mean))
  zpred <- t(apply(ssSamples$zpred, c(1,2), mean))

  ww <- grep(pattern = 'beta', colnames(ssGibbs.jags))
  if(!is.null(colnames(x))) colnames(ssGibbs.jags)[ww] <- colnames(x)
  return(list(model=ssModel,
              chains=ssGibbs.jags,
              nBurnin= nBurnin,
              nGibbs=nGibbs,
              latentGibbs = latentGibbs,
              zpred = zpred,
              rawsamples = ssSamples,
              data =list(x = x,
                         z = z,
                         connect = connect,
                         # HeadTail = HeadTail,
                         nBurnin = nBurnin,
                         nGibbs = nGibbs,
                         n.chains=n.chains,
                         n.adapt = n.adapt)))
}

