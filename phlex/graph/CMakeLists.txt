add_library(phlex_graph SHARED serializer_node.cpp)
phlex_apply_symbol_visibility(phlex_graph)
target_include_directories(phlex_graph PRIVATE ${PROJECT_SOURCE_DIR})
target_link_libraries(
  phlex_graph PRIVATE Boost::boost TBB::tbb phlex::utilities fmt::fmt
  )

# Interface library
add_library(phlex_graph_int INTERFACE)
target_include_directories(
  phlex_graph_int INTERFACE "$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}>"
                            "$<INSTALL_INTERFACE:include>"
  )
target_link_libraries(phlex_graph_int INTERFACE phlex_graph TBB::tbb)

add_library(phlex::graph ALIAS phlex_graph_int)

install(TARGETS phlex_graph)
