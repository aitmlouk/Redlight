suppressMessages(library(shiny))
suppressMessages(library(ggplot2))
suppressMessages(library(ggmap))
suppressMessages(library(RJSONIO))
suppressMessages(library(png))
suppressMessages(library(grid))
suppressMessages(library(RCurl))
suppressMessages(library(plyr))
suppressMessages(library(markdown))
suppressMessages(library(rCharts))
suppressMessages(library(parallel))
library(xts)
library(raster)
library(sp)
library(rgeos)
library(rgdal)

#Load data files
load(file = "./data/redlight2.rda")
load(file = "./data/redlight.rda")
load(file = "./data/total.rda")
load(file = "./data/totalALL.rda")
load(file = "./data/ticket.rda")

#xtsmelt function is for time series manipulation for highcharts
xtsMelt <- function(data) {
  require(reshape2)
  #translate xts to time series to json with date and data
  #for this behavior will be more generic than the original
  #data will not be transformed, so template.rmd will be changed to reflect
  #convert to data frame
  data.df <- data.frame(cbind(format(index(data),"%Y-%m-%d"),coredata(data)))
  colnames(data.df)[1] = "date"
  data.melt <- melt(data.df,id.vars=1,stringsAsFactors=FALSE)
  colnames(data.melt) <- c("date","indexname","value")
  #remove periods from indexnames to prevent javascript confusion
  #these . usually come from spaces in the colnames when melted
  data.melt[,"indexname"] <- apply(matrix(data.melt[,"indexname"]),2,gsub,pattern="[.]",replacement="")
  return(data.melt)
  #return(df2json(na.omit(data.melt)))
}


## Define server logic required to summarize and view the selected dataset
shinyServer(function(input, output) {
  
  ## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  ## Reactive Functions
  ## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  
  
  #Accident data for RLC
  datesubset <- reactive({
      total1 <- NULL
      #Only run if we are getting input data for RLC#
      if (input$Address == "") {        
      total1 <- subset(total, PosixDate > as.POSIXct(strptime(input$startdate, format="%Y-%m-%d")) & PosixDate < as.POSIXct(strptime(input$enddate, format="%Y-%m-%d")))
         #Catches if input is null
         if (is.null(input$Intersection)) {
            temp.inter <- 2
            print ("hi")}
          else 
          {temp.inter <- grep (input$Intersection,df1$INTERSECTION) }   
          #subset data to a specific intersection
          total1 <- subset(total1, total1$IntersectionID == temp.inter)}
          return(total1)
          })
  
  #Ticket Data for RLC
  datesubsetticket <- reactive({
    temp <- NULL
    #Only run if we are getting input data for RLC#
    if (input$Address == "") { 
    temp <- subset(ticket, PosixDate > as.POSIXct(strptime(input$startdate, format="%Y-%m-%d")) & PosixDate < as.POSIXct(strptime(input$enddate, format="%Y-%m-%d")))
  
           #Catches if input is null
    if (is.null(input$Intersection)) 
      {tempinter <- 2}
     else 
     {tempinter <- grep (input$Intersection,df1$INTERSECTION)}
     
               #subset data to a specific intersection
    temp <- subset(temp, temp$IntersectionID == tempinter)}
    return(temp)
  })
  
  #Accident data for All
  datesubsetALL <- reactive({
    total1 <- NULL
    #Only run if we are getting input data for RLC#
    if (input$Address != "") {        
      #Subset by date
      total1 <- subset(totalALL, PosixDate > as.POSIXct(strptime(input$startdate, format="%Y-%m-%d")) & PosixDate < as.POSIXct(strptime(input$enddate, format="%Y-%m-%d")))
      #Conversion to planar for all data
      spg <- total1
      coordinates(spg) <- ~ CrashCoordindateY + CrashCoordinateX
      proj4string(spg) = CRS("+proj=tmerc +lat_0=36.66666666666666 +lon_0=-90.16666666666667 +k=0.9999411764705882 +x_0=700000 +y_0=0 +ellps=GRS80 +datum=NAD83 +to_meter=0.3048006096012192 +no_defs")
      #Get address and convert to planaar
      splocations <- geocode(input$Address)
      coordinates(splocations) <- ~ lon + lat  #for red light cameras
      proj4string(splocations) = CRS("+init=epsg:4326")
      splocations = spTransform(splocations, CRS("+proj=tmerc +lat_0=36.66666666666666 +lon_0=-90.16666666666667 +k=0.9999411764705882 +x_0=700000 +y_0=0 +ellps=GRS80 +datum=NAD83 +to_meter=0.3048006096012192 +no_defs"))
      #Get accidents within buffer
      points <- gBuffer(splocations, width=input$Buffer)
      subtotal <-spg[!is.na(over(spg,as(points,"SpatialPolygons"))),]
      total1 <- as.data.frame(subtotal)
      total1 <- total1[order(total1$PosixDate),]
    }
      return(total1)
  })
  
  
    ## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  ## Outputs
  ## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  
  
  ## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  ## Accident Data Table
  ## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  output$datatable <- renderDataTable({
    if (input$Address == "") {datesubset()}
   else {datesubsetALL()}
    }, options = list(aLengthMenu = c(10, 25, 50, 100, 1000), iDisplayLength = 10))
  
 
  ## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  ## Output 1 - Accident Graphs
  ## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  
  #Use this to select time frame for analysis
  output$accperiod <- renderUI({selectInput("aperiod", "Choose Period to Analyze:", choice = c("yearly", "monthly","weekly", "daily"))})
  
  output$accidents <- renderChart2({
    
      #Catches if time period is null
    if (is.null(input$aperiod)) {temp.aperiod <- "yearly"}
    else {temp.aperiod <- input$aperiod }
    
    if (input$Address == "") {
      xtstemp <- datesubset() 
      locname = input$Intersection
      }
    else {xtstemp <- datesubsetALL()
          xtstemp <- cbind(IntersectionID = 2, xtstemp)
          locname = input$Address
    }
  #Convert to XTS time series for calculations
    
    totalxts1 <- xts(xtstemp$IntersectionID>1,xtstemp$PosixDate,order.by=as.POSIXct(xtstemp$PosixDate))

    if (temp.aperiod == "daily") {TotalAccidents <- apply.daily(totalxts1,sum)}
    if (temp.aperiod == "weekly") {TotalAccidents <- apply.weekly(totalxts1,sum)}
    if (temp.aperiod == "monthly") {TotalAccidents <- apply.monthly(totalxts1,sum)}
    if (temp.aperiod == "yearly") {TotalAccidents <- apply.yearly(totalxts1,sum)}

#Convert data using xtsMelt for highcharts plot
  ust.melt <- na.omit(xtsMelt(TotalAccidents))
  ust.melt$date2 <- as.Date(ust.melt$date, format = "%Y-%m-%d")
  ust.melt$Accidents <- as.numeric(as.character(ust.melt$value))
  ust.melt$date4  <- as.numeric(as.POSIXct(ust.melt$date2, origin="1970-01-01")) * 1000
  
#Highchart plot
  h1 <- hPlot(
    Accidents ~ date4,  #or x="date", y="value"
    data = ust.melt, 
    color = '#4572A7',
    type = 'spline',
    title = paste("Accidents at",locname)
  ) 
  h1$xAxis(type = "datetime")
  
  h1
})

#Blank space between graphs
output$space <- renderUI({helpText(HTML("<br>"))})

  ## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  ## Ticket Plot
  ## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 
 output$ticketchart <- renderChart2({
  
  #Check to see if this is a RLC intersection#
  if (input$Address != "") {return()}
  else {
            #Catches if time period is null
         if (is.null(input$aperiod)) {temp.aperiod <- "yearly"}
         else {temp.aperiod <- input$aperiod }
      
      #Convert to XTS time series for calculations
       xtstemp <- datesubsetticket() 
       totalxts1 <- xts(xtstemp$IntersectionID>1,xtstemp$PosixDate)
         if (temp.aperiod == "daily") {TotalTickets <- apply.daily(totalxts1,sum)}
         if (temp.aperiod == "weekly") {TotalTickets <- apply.weekly(totalxts1,sum)}
         if (temp.aperiod == "monthly") {TotalTickets <- apply.monthly(totalxts1,sum)}
         if (temp.aperiod == "yearly") {TotalTickets <- apply.yearly(totalxts1,sum)}
      
      #Convert data using xtsMelt for highcharts plot
      ust.melt <- na.omit(xtsMelt(TotalTickets))
      ust.melt$date2 <- as.Date(ust.melt$date, format = "%Y-%m-%d")
      ust.melt$Tickets <- as.numeric(as.character(ust.melt$value))
      ust.melt$date4  <- as.numeric(as.POSIXct(ust.melt$date2, origin="1970-01-01")) * 1000
      
      #Highchart plot
      h2 <- hPlot(
        Tickets ~ date4,  #or x="date", y="value"
        data = ust.melt,
        type = 'spline',
        title = paste("Tickets at",input$Intersection)
      ) 
      h2$xAxis(type = "datetime")
      h2
}
})


output$heading <- renderUI({helpText(HTML("<b>Some statistics for the intersection:</b><br>"))})
## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
## Printed Outputs of Analysis
## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Total Tickets
output$totaltickets <- renderText({
  temp <- datesubsetticket()
  total <- nrow (temp)
  paste("Total Tickets:", total)
})

output$mapinfo <- renderText({
  paste("Zoom in and hover over black dots for accident details.  The blue marker indicates the central point for analysis.  Note: Sometimes (especially with intersections), the Google geocode is not in the middle of the intersection, thus affecting results.")
})

#Total Tickets for Map page 
output$totaltickets2 <- renderText({
  if (input$Address == "") {temp <- datesubset()}
  else {return()}
  total <- nrow (temp)
  
  paste("Total Tickets over Date Range:", total)
})

#Total Accidents
 output$totalaccidents <- renderText({
   if (input$Address == "") {temp <- datesubset()}
   else {temp <- datesubsetALL()}
   total <- nrow (temp)
   paste("Total Accidents over Date Range:", total)
 })

#Total Accidents for Map page
output$totalaccidents2 <- renderText({
  if (input$Address == "") {temp <- datesubset()}
  else {temp <- datesubsetALL()}
  total <- nrow (temp)
  paste("Total Accidents over Date Range:", total)
})

#Total Killed
  output$totalkilled <- renderText({
    if (input$Address == "") {temp <- datesubset()}
    else {temp <- datesubsetALL()}
    totalkilled <- sum(temp$totalkilled)
    paste("Total Killed over Date Range:", totalkilled)
  })

#Total Injured
 output$totalinjured <- renderText({
   if (input$Address == "") {temp <- datesubset()}
   else {temp <- datesubsetALL()}
   totalinjured <- sum(temp$total.injured)
   paste("Total Injured over Date Range:", totalinjured)
 })

output$heading1 <- renderUI({helpText(HTML("<br><br><b>Collision Type Totals during Date Range:</b>"))})

######
# Table - Totals of Collision Type
#####

#Table for Collision Type 

 output$totalcolltype <- renderDataTable({
   if (input$Address == "") {
     temp <- datesubset()
     collisiontype <- (temp$collisiontypecode)
     collisioncodes <- c(Pedestrian=1, Pedalcyclist=2, Train=3, Animal=4,Overturned=5, 
                         "Fixed Object"=6, "Other Object"=7, "Other non-collision"=8, "Parked Motor vehicle"=9, Turning= 10,
                         "Read-end"=11, "Sideswipe-same direction"=12, "Sideswipe-opposite direction"=13, "Head-on"=14, Angle=15)
     CollisionType <- names(collisioncodes)[match(collisiontype,collisioncodes)]
     temp1 <- table(CollisionType)
     as.data.frame(temp1)
   }
   else {
          temp <- datesubsetALL()
          temp3 <- table(temp$CollisionType)
          as.data.frame(temp3)
          }

 },options=list(bFilter = FALSE, bPaginate = FALSE))

output$heading2 <- renderUI({helpText(HTML("<br><br><b>Breakdown of Collision Types over Period:</b>"))})
#
######
# Table - Breakdown of Collision Types over Period
#####

output$totalcolltype2 <- renderDataTable({

  if (input$Address == "") {
        xtstemp <- datesubset()
              for (n in seq(1,15,1))
            {
              # Convert to xts
              
              collisionxts <-xts(xtstemp$collisiontypecode==n,xtstemp$PosixDate)
              # Get Period
              if (is.null(input$aperiod)) {temp.aperiod <- "yearly"}
              else {temp.aperiod <- input$aperiod }
              #Convert to XTS time series for calculations
              if (temp.aperiod == "daily") {collisiontype <- apply.daily(collisionxts,sum)}
              if (temp.aperiod == "weekly") {collisiontype <- apply.weekly(collisionxts,sum)}
              if (temp.aperiod == "monthly") {collisiontype <- apply.monthly(collisionxts,sum)}
              if (temp.aperiod == "yearly") {collisiontype <- apply.yearly(collisionxts,sum)}
              collisiondf<-data.frame(index(collisiontype),coredata(collisiontype[,1]))
              if (n==1) {temp <- collisiondf}
              else {temp <- cbind(temp,collisiondf[,2])}
            }
          colnames(temp) <- c("Date","Pedestrian","Pedalcyclist","Train","Animal","Overturned", 
                              "Fixed Object", "Other Object", "Other non-collision", "Parked Motor vehicle", "Turning",
                              "Read-end", "Sideswipe-same direction", "Sideswipe-opposite direction", "Head-on", "Angle")
          temp$Date <- as.character(temp$Date)
        
        
          temp}
  else {
        xtstemp <-datesubsetALL()
        #xtstemp$CollisionType <- as.numeric(xtstemp$CollisionType)
        list <- unique(xtstemp$CollisionType)
        for (n in seq(1,15,1))
        {
          # Convert to xts
          
          collisionxts <-xts(xtstemp$collisiontypecode==n,xtstemp$PosixDate)
          # Get Period
          if (is.null(input$aperiod)) {temp.aperiod <- "yearly"}
          else {temp.aperiod <- input$aperiod }
          #Convert to XTS time series for calculations
          if (temp.aperiod == "daily") {collisiontype <- apply.daily(collisionxts,sum)}
          if (temp.aperiod == "weekly") {collisiontype <- apply.weekly(collisionxts,sum)}
          if (temp.aperiod == "monthly") {collisiontype <- apply.monthly(collisionxts,sum)}
          if (temp.aperiod == "yearly") {collisiontype <- apply.yearly(collisionxts,sum)}
          collisiondf<-data.frame(index(collisiontype),coredata(collisiontype[,1]))
          if (n==1) {temp <- collisiondf}
          else {temp <- cbind(temp,collisiondf[,2])}
        }
        colnames(temp) <- c("Date","Pedestrian","Pedalcyclist","Train","Animal","Overturned", 
                            "Fixed Object", "Other Object", "Other non-collision", "Parked Motor vehicle", "Turning",
                            "Read-end", "Sideswipe-same direction", "Sideswipe-opposite direction", "Head-on", "Angle")
        temp$Date <- as.character(temp$Date)
        temp}
  },options=list(bFilter = FALSE))


## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
## Output 1 - Ticket Data Table
## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

output$datatickettable <- renderDataTable({
  datesubsetticket() 
}, options = list(aLengthMenu = c(10, 25, 50, 100, 1000), iDisplayLength = 10))


## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
## Output 1 - RLC Data Table
## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

output$dataRLC <- renderDataTable({
  df1 
}, options = list(aLengthMenu = c(10, 25, 50, 100, 1000), iDisplayLength = 10))



## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
## Output - Map of Accidents
## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

output$map <- renderMap({

  if (input$Address == "") {df3<-datesubset()
                            df3 <- rename(df3, c("CrashLatitude"="lat", "CrashLongitude"="lon"))
                            #Get the center from the first value
                            map.center <- head(df3,n=1)
                            map.center <- map.center[c("lat","lon")]
                          }
  else    {df3<-datesubsetALL()
           df3 <- rename(df3, c("CrashLatitude"="lat", "CrashLongitude"="lon"))
           map.center <- geocode(input$Address)}
  
#Get text for labels
collisiontype <- (df3$collisiontypecode)
collisioncodes <- c(Pedestrian=1, Pedalcyclist=2, Train=3, Animal=4,Overturned=5, 
                    "Fixed Object"=6, "Other Object"=7, "Other non-collision"=8, "Parked Motor vehicle"=9, Turning= 10,
                    "Read-end"=11, "Sideswipe-same direction"=12, "Sideswipe-opposite direction"=13, "Head-on"=14, Angle=15)
df3$CollisionType <- names(collisioncodes)[match(collisiontype,collisioncodes)]

#Infor for popup tags
df3$color <- "#050505"
df3$popup <- paste0("<p>Collision Type:  ", df3$CollisionType, 
                    "<br>Total Injured:  ", df3$total.injured, 
                    "<br>Total Killed:  ", df3$totalkilled)

#Convert to list for JSON
tmp.data <- apply(df3, 1, as.list)


map <- Leaflet$new()
map$setView(c(map.center$lat,map.center$lon), zoom = 15)
#map$setView(c(41,-87), zoom = 13)
map$tileLayer(provider = 'Stamen.TonerLite')
map$tileLayer(provider = 'OpenStreetMap.Mapnik')
map$geoJson(toGeoJSON(tmp.data, lat = 'lat', lon = 'lon'),
            onEachFeature = '#! function(feature, layer){
            layer.bindPopup(feature.properties.popup)
} !#',
            pointToLayer =  "#! function(feature, latlng){
            return L.circleMarker(latlng, {
            radius: 8,
            fillColor: feature.properties.color || 'red', 
            color: '#000',
            weight: 1,
            fillOpacity: 0.8
            })
            } !#"           
)
map$marker(
    c(map.center$lat,map.center$lon),
    bindPopup = 'Center'
 )
map$enablePopover(TRUE)
map

})


  })
    
