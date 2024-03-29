% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/hyaggregate_utils.R
\name{describe_hydrofabric}
\alias{describe_hydrofabric}
\title{Describe Hydrofabric
Describes a hydrofabric in terms of flowpath and catchment count. If they
are unequal, FALSE is returned. If equal TRUE is returned. Messages can optionally
be emitted.}
\usage{
describe_hydrofabric(network_list, verbose = TRUE)
}
\arguments{
\item{network_list}{a list containing flowpaths and catchments}

\item{verbose}{should messages be emitted?}
}
\value{
boolean condition
}
\description{
Describe Hydrofabric
Describes a hydrofabric in terms of flowpath and catchment count. If they
are unequal, FALSE is returned. If equal TRUE is returned. Messages can optionally
be emitted.
}
