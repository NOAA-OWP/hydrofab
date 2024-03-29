#' Generate Catchment Network Table
#' @param gpkg a  hydrofabric gpkg
#' @return data.frame with ID, toID, length, area, and levelpath
#' @export
#' @importFrom sf st_drop_geometry write_sf
#' @importFrom dplyr select 


add_flowpath_edge_list = function(gpkg){
  
  gf = read_hydrofabric(gpkg, realization = "flowpaths")
  cn = select(st_drop_geometry(gf[[1]]), id, toid)
  write_sf(cn, gpkg, "flowpath_edge_list")
  return(gpkg)
}


#' Extract nexus locations for Reference POIs
#' @param gpkg a reference hydrofabric gpkg
#' @param type the type of desired POIs
#' @param verbose should messages be emitted?
#' @return data.frame with ID, type columns
#' @export
#' @importFrom sf read_sf st_drop_geometry
#' @importFrom dplyr mutate_at vars mutate group_by ungroup filter distinct slice
#' @importFrom tidyr pivot_longer separate_longer_delim


hl_to_outlet = function(gpkg,
                        type = c('HUC12', 'Gages', 'TE', 'NID', 'WBIn', 'WBOut'),
                        verbose = TRUE){
  
  valid_types = c('HUC12', 'Gages', 'TE', 'NID', 'WBIn', 'WBOut', "Conf", "Term", "Elev", "Travel", "Con")
  
  if(!all(type %in% valid_types)){
    bad_ids = type[!which(type %in% valid_types)]
    stop(bad_ids, " are not valid POI types. Only ", paste(valid_types, collapse = ", "), " are valid")
  }
  
  if(is.null(type)){ type = valid_types }
  
  poi_layer = grep("POIs_*", st_layers(gpkg)$name, value = TRUE)
  
  
  hl  = read_sf(gpkg, poi_layer) %>% 
    mutate(hl_id = as.integer(id)) %>% 
    select(COMID, hl_id, paste0("Type_", type)) %>%
    mutate_at(vars(matches("Type_")), as.character) %>% 
    mutate(nas = rowSums(is.na(.))) %>% 
    filter(nas != length(type))
  
  xx = select(hl, hl_id) %>% 
    group_by(hl_id) %>% 
    slice(1) %>% 
    ungroup()
             
  nexus_locations = st_drop_geometry(hl) %>%
    select(COMID, hl_id, paste0("Type_", type)) %>%
    mutate_at(vars(matches("Type_")), as.character) %>%
    group_by(COMID, hl_id) %>%
    ungroup() %>%
    pivot_longer(-c(hl_id, COMID)) %>%
    filter(!is.na(value)) %>%
    mutate(hl_reference = gsub("Type_", "", name)) %>% 
    select(id = COMID, hl_id, hl_reference, hl_link = value) %>% 
    distinct(hl_id, hl_reference, hl_link, .keep_all = TRUE) %>% 
    left_join(xx, by = "hl_id", relationship = "many-to-many") %>% 
    separate_longer_delim(hl_link,  delim = ",")
  
  hyaggregate_log("INFO", glue("{length(unique(nexus_locations$hl_id))} distinct POIs found."), verbose)
  
  nexus_locations
}

#' Add a mapped_POI layer to network_list
#'
#' @param network_list a list with flowpath and catchment data
#' @param refactored_gpkg a (optional) path to 
#' @param verbose should messages be emited?
#' @return list()
#' @export
#' @importFrom dplyr filter select mutate mutate_at vars group_by ungroup slice right_join starts_with
#' @importFrom tidyr pivot_longer 
#' @importFrom nhdplusTools get_node

add_mapped_hydrolocations = function(network_list, 
                           type = c('HUC12', 'Gages', 'TE', 'NID', 'WBIn', 'WBOut'),
                           refactored_gpkg = NULL, 
                           verbose = TRUE){
  
  hl_to_outlet(refactored_gpkg) %>% 
    mutate(hl_id = as.integer(hl_id)) %>% 
    left_join(select(hl, hl_id), by = "hl_id")
              
  if(!is.null(refactored_gpkg)){
    
      hl= read_sf(refactored_gpkg, "mapped_POIs") %>% 
        rename(hl_id = identifier)
      
      pois = pois %>% 
        filter(hl_id %in% as.numeric(network_list$flowpaths$hl_id)) %>% 
        st_drop_geometry() %>% 
        select(hl_id, paste0("Type_", type)) %>%
        mutate_at(vars(matches("Type_")), as.character) %>%
        group_by(hl_id) %>%
        ungroup() %>%
        pivot_longer(-c(hl_id)) %>%
        filter(!is.na(value)) %>%
        mutate(type = gsub("Type_", "", name)) %>% 
        select(hl_id, type, value) %>% 
        filter(type %in% !!type) %>% 
        distinct() %>% 
        left_join(select(hl, hl_id), by = "hl_id")
      
    }

  network_list$mapped_POIs = hl
  
  return(network_list)
  
}

#' Generate Lookup table for refactored or aggregated network
#' @param gpkg character path to gpkg containing aggregated network. Omit for 
#' refactored network lookup table creation.
#' @param refactored_gpkg character path to the gpkg for the refactored network 
#' used to create the aggregate network. If no aggregatedd gpkg is passed in, a 
#' lookup table will be added to this gpkg.
#' @param reconciled_layer character path layer name containing fully 
#' reconciled flowpaths. Ignored for aggregated network lookup table creation.
#' @return file path to modified gpkg
#' @export
#' @importFrom sf read_sf st_drop_geometry write_sf
#' @importFrom dplyr mutate select full_join left_join
#' @importFrom tidyr unnest
#' 
add_lookup_table = function(gpkg = NULL,
                                 refactored_gpkg = NULL,
                                 reconciled_layer = "flowpaths") {
  
  if(is.null(gpkg) & !is.null(refactored_gpkg)) {
    # create lookup for ref flowlines to use in the non-dendritic steps
    refactor_lookup <- st_drop_geometry(read_sf(refactored_gpkg, reconciled_layer)) %>%
      dplyr::select(ID, member_COMID) %>%
      dplyr::mutate(member_COMID = strsplit(member_COMID, ",")) %>%
      tidyr::unnest(cols = member_COMID) %>%
      dplyr::mutate(NHDPlusV2_COMID = as.integer(member_COMID)) %>% # note as.integer truncates
      dplyr::rename(reconciled_ID = ID)
    
    if(is.character(refactor_lookup$reconciled_ID)) 
      refactor_lookup$reconciled_ID <- as.integer(refactor_lookup$reconciled_ID)
    
    lookup_table <- tibble::tibble(NHDPlusV2_COMID = unique(as.integer(refactor_lookup$member_COMID))) %>%
      dplyr::left_join(refactor_lookup, by = "NHDPlusV2_COMID") 
    
    write_sf(lookup_table, refactored_gpkg, "lookup_table")
    
    return(refactored_gpkg)
  }
  
  if (is.null(gpkg) | is.null(refactored_gpkg)) {
    stop("hydrofabrics must be provided.")
  }
  
  outlets = poi_to_outlet(refactored_gpkg, verbose = FALSE)
  
  lu = read_sf(refactored_gpkg, "lookup_table")
  
  nl = read_hydrofabric(gpkg)
  
  if(!"member_comid" %in% names(nl$flowpaths)) {

    nl$flowpaths <- left_join(nl$flowpaths,
                              select(lu, reconciled_ID, member_COMID) %>%
                                group_by(reconciled_ID) %>%
                                summarise(member_comid = list(member_COMID)) %>%
                                pack_set("member_comid"), by = c("id" = "reconciled_ID"))
  }
  
  if(!"poi_id" %in% names(nl$flowpaths)) {
    nl$flowpaths <- left_join(nl$flowpaths, 
                              select(outlets, id, poi_id),
                              by = "id")
  }
  
  outlets <- outlets %>% 
    select(POI_ID = poi_id, POI_TYPE = type, POI_VALUE = value)
  
  lu <- lu %>%
    select(NHDPlusV2_COMID, reconciled_ID)
  
  vaa = suppressMessages({
    get_vaa("hydroseq", updated_network = TRUE) %>%
      rename(NHDPlusV2_COMID = comid)
  }) 

  lu2 = nl$flowpaths %>%
    st_drop_geometry() %>%
    select(
      aggregated_ID = id,
      toID          = toid,
      member_COMID  = member_comid,
      divide_ID     = id,
      POI_ID        = poi_id,
      mainstem_id = levelpathid) %>%
    mutate(member_COMID = strsplit(member_COMID, ","),
           POI_ID = as.integer(POI_ID)) %>%
    unnest(col = 'member_COMID') %>%
    mutate(NHDPlusV2_COMID_part = sapply( strsplit(member_COMID, "[.]"), FUN = function(x){ x[2] }),
           NHDPlusV2_COMID_part = ifelse(is.na(NHDPlusV2_COMID_part), 1L, as.integer(NHDPlusV2_COMID_part)),
           NHDPlusV2_COMID = sapply( strsplit(member_COMID, "[.]"), FUN = function(x){ as.numeric(x[1]) })
    ) %>%
    full_join(lu, by = "NHDPlusV2_COMID") %>%
    left_join(vaa, by = "NHDPlusV2_COMID") %>%
    group_by(aggregated_ID) %>%
    arrange(hydroseq) %>%
    mutate(POI_ID  = as.character(c(POI_ID[1],  rep(NA, n()-1)))) %>%
    ungroup() %>%
    select(-hydroseq, - member_COMID) %>%
    left_join(outlets, by = "POI_ID") %>%
    select(NHDPlusV2_COMID, 
           NHDPlusV2_COMID_part,
           reconciled_ID,
           aggregated_ID, 
           toID, 
           mainstem = mainstem_id,
           POI_ID, 
           POI_TYPE, 
           POI_VALUE)
  
  write_sf(lu2, gpkg, "lookup_table")
  
  return(gpkg)
  
}


#add_infered_nexus