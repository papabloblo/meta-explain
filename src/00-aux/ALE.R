#' ALE ALGORITHM IMPLEMENTATION
#' 
#' TODO: 
#'    - Input to ale_by_task_feature: A list with de predictor 
#'        function of each model
#'    - 
#'    


library(tidyverse)


quantiles_xALE <- function(df, features, n = 30, epsilon = 0.01){
  xALE <- list()
  for (f in features){
    xALE[[f]] <- quantile(df[[f]], probs = seq(0, 1, length.out = n))
    xALE[[f]][1] <- xALE[[f]][1] - epsilon
    xALE[[f]][n] <- xALE[[f]][n] + epsilon
  }
  return(xALE)
}


grid_xALE <- function(df, features, n = 30, epsilon = 0.01){
  xALE <- list()
  for (task in unique(df$id_task)){
    for (f in features){
      df_aux <- df[df$id_task == task,][[f]]
      xALE[[task]][[f]] <- seq(from = min(df_aux) - epsilon,
                       to = max(df_aux) + epsilon,
                       length.out = n)
    }  
  }
  
  return(xALE)
}

ale <- function(df, model, features, xALE = NA){
  
  if (is.na(xALE[1])){
    xALE <- quantiles_xALE(df, features)
  }
  
  ale_list <- list()
  
  for (x in features){
    df_aux <- df
    
    n_xALE <- numeric(length(xALE[[x]])-1)
    for (i in 1:(length(n_xALE))){
      n_xALE[i] <- sum(df[[x]] > xALE[[x]][i] & df[[x]] <= xALE[[x]][i+1])
    }
    
    df_aux$z0 <- NA
    df_aux$z1 <- NA
    df_aux$id <- NA
    
    for(i in 1:nrow(df_aux)){
      id_zk <- which(df_aux[[x]][i] <= xALE[[x]][1:(length(xALE[[x]])-1)])[1]
      df_aux$id[i] <- id_zk
      df_aux$z0[i] <- xALE[[x]][id_zk]
      df_aux$z1[i] <- xALE[[x]][id_zk+1]
    }
    
    df_aux$y_z0 <- NA
    df_aux$y_z1 <- NA
    
    df_z0 <- df_aux
    df_z0[x] <- NULL 
    names(df_z0)[names(df_z0) == "z0"] <- x
    
    df_aux$y_z0 <- predict(model, newdata = df_z0)
    
    df_z1 <- df_aux
    df_z1[x] <- NULL 
    names(df_z1)[names(df_z0) == "z1"] <- x
    
    df_aux$y_z1 <- predict(model, newdata = df_z1)
    
    df_aux <- df_aux %>% 
      mutate(ale = y_z1 - y_z0) %>% 
      group_by(z1) %>% 
      summarise(
        n = n(),
        sum_ale = sum(ale),
        ale = sum_ale/n) %>% 
      arrange(z1) %>% 
      mutate(ale_cum = cumsum(ale),
             ale_cum_cent = sum(n*ale_cum, na.rm = TRUE)/sum(n, na.rm = TRUE),
             ale_final = ale_cum - ale_cum_cent) %>% 
      na.omit()
    
    ale_list[[x]] <- df_aux %>% 
      select(z1, n, ale_final) %>% 
      rename("x" = "z1", "ale" = "ale_final")
  }
  return(ale_list)
}


ale_plot_by_var <- function(curve_ale, x, point = FALSE){
  
  min_x <- min(min(x), min(curve_ale$x))
  max_x <- max(max(x), max(curve_ale$x))
  
  p1 <- curve_ale %>% 
  ggplot(aes(x = x,
             y = ale)) + 
    geom_line() +

    scale_x_continuous(limits = c(min_x, max_x)) +
    facet_wrap(
      vars(var))

  if (isTRUE(point)) p1 <- p1 + geom_point()    

  p2 <- data.frame(x = x) %>%
    ggplot(aes(x = x)) + 
    geom_histogram() +
    scale_x_continuous(limits = c(min_x, max_x)) +
    theme_void()
  
  p3 <- curve_ale %>% 
    bind_rows(
      data.frame(
        x = c(min_x, max_x),
        n = c(
          curve_ale$n[curve_ale$x == min(curve_ale$x)],
          curve_ale$n[curve_ale$x == max(curve_ale$x)])
        )
      ) %>%
    arrange(x) %>% 
    mutate(xend = lead(x)) %>% 
    ggplot(aes(xmin = x, xmax = xend, ymin = 0, ymax = n)) + 
    geom_rect(color = "white") +
    scale_x_continuous(limits = c(min_x, max_x)) +
    theme_void()
  
  return(p1 + p2 + p3 + plot_layout(heights = c(5,1,1)))
  
}


ale_plot <- function(ale_by_var, df_original, features = "all", point = FALSE) {
  aux <- ale_by_var
  
  for (x in names(aux)){
    aux[[x]]$var <- x
  }
  
  if (features[1] == "all") features <- names(ale_by_var)

  plot_list <- list()
  for (f in features){
    curve_ale <- bind_rows(aux) %>% filter(var == f)
    x <- df_original[[f]]
    
    plot_list[[f]] <- ale_plot_by_var(curve_ale, x, point = point)
    
  }
  
  return(wrap_plots(plot_list))
}



ale_by_task_feature <- function(df, model = randomForest, xALE, ...) {
  
  list_ales <- list()
  for (task in unique(df$id_task)){
    df_task <- df[df$id_task == task, ]
    df_task$id_task <- NULL
    list_ales[[task]] <- ale(df_task, 
                             model = model[[task]]$model, 
                             xALE = xALE[[task]],
                             ...)
  }
  
  if (is.null(names(list_ales))) names(list_ales) <- 1:length(list_ales)
  
  aux <- list()
  for (task in names(list_ales)){
    for (x in names(list_ales[[task]])){
      list_ales[[task]][[x]]$task <- task
      list_ales[[task]][[x]]$feature <- x
    }
    aux[[task]] <- bind_rows(list_ales[[task]])
  }
  
  return(bind_rows(aux))

}
