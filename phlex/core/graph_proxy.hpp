#ifndef PHLEX_CORE_GRAPH_PROXY_HPP
#define PHLEX_CORE_GRAPH_PROXY_HPP

/// @file phlex/core/graph_proxy.hpp
///
/// @brief Defines the graph_proxy class, a fluent interface for building Phlex graphs.

#include "phlex/concurrency.hpp"
#include "phlex/core/concepts.hpp"
#include "phlex/core/glue.hpp"
#include "phlex/core/node_catalog.hpp"
#include "phlex/core/registrar.hpp"
#include "phlex/metaprogramming/delegate.hpp"

#include "oneapi/tbb/flow_graph.h"

#include <concepts>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace phlex::experimental {
  class configuration;
  // ==============================================================================
  // Registering user functions

  /// @brief A fluent interface for constructing and configuring a Phlex graph.
  ///
  /// The `graph_proxy` provides a set of methods for adding different types of
  /// nodes (e.g., transforms, folds, predicates) to the underlying TBB flow graph.
  /// It is the primary way users define the structure and logic of their
  /// data-processing pipeline.
  ///
  /// @tparam T The type of an object that member-function-based algorithms are
  ///           bound to. Use `void_tag` if algorithms are free functions or
  ///           stateless lambdas.
  template <typename T>
  class graph_proxy {
  public:
    template <typename>
    friend class graph_proxy;

    /// @brief Constructs a `graph_proxy` for unbound algorithms.
    ///
    /// This constructor is used when the processing graph consists of free
    /// functions or stateless lambdas. It requires the `T` template parameter
    /// to be `void_tag`.
    graph_proxy(configuration const& config,
                tbb::flow::graph& g,
                node_catalog& nodes,
                std::vector<std::string>& errors)
      requires(std::same_as<T, void_tag>)
      : config_{&config}, graph_{g}, nodes_{nodes}, errors_{errors}
    {
    }

    /// @brief Creates a new `graph_proxy` bound to a stateful object.
    ///
    /// This function allows you to create a `graph_proxy` that is associated
    /// with a specific object. When you define algorithms using member functions
    /// of this object, the `graph_proxy` will ensure they are correctly invoked.
    ///
    /// @tparam U The type of the object to bind to.
    /// @tparam Args The types of arguments for constructing the object.
    /// @param args Arguments for constructing the object of type `U`.
    /// @return A new `graph_proxy` bound to an instance of `U`.
    template <typename U, typename... Args>
    graph_proxy<U> make(Args&&... args)
    {
      return graph_proxy<U>{
        config_, graph_, nodes_, std::make_shared<U>(std::forward<Args>(args)...), errors_};
    }

    /// @brief Adds a fold algorithm to the graph.
    ///
    /// @tparam InitArgs The types of arguments for initializing the fold's state.
    /// @param name The name of the fold node.
    /// @param f The fold function or functor. Must satisfy the `is_fold_like` concept.
    /// @param c The concurrency level for this node.
    /// @param partition The partition key for stateful folds.
    /// @param init_args Arguments for initializing the fold's state.
    /// @return An object for connecting this node to others in the graph.
    template <typename... InitArgs>
    auto fold(std::string name,
              is_fold_like auto f,
              concurrency c = concurrency::serial,
              std::string partition = "job",
              InitArgs&&... init_args)
    {
      return create_glue().fold(std::move(name),
                                std::move(f),
                                c,
                                std::move(partition),
                                std::forward<InitArgs>(init_args)...);
    }

    /// @brief Adds an observer to the graph.
    ///
    /// @param name The name of the observer node.
    /// @param f The observer function or functor. Must satisfy the `is_observer_like` concept.
    /// @param c The concurrency level for this node.
    /// @return An object for connecting this node to others in the graph.
    auto observe(std::string name, is_observer_like auto f, concurrency c = concurrency::serial)
    {
      return create_glue().observe(std::move(name), std::move(f), c);
    }

    /// @brief Adds a predicate to the graph.
    ///
    /// @param name The name of the predicate node.
    /// @param f The predicate function or functor. Must satisfy the `is_predicate_like` concept.
    /// @param c The concurrency level for this node.
    /// @return An object for connecting this node to others in the graph.
    auto predicate(std::string name, is_predicate_like auto f, concurrency c = concurrency::serial)
    {
      return create_glue().predicate(std::move(name), std::move(f), c);
    }

    /// @brief Adds a transform to the graph.
    ///
    /// @param name The name of the transform node.
    /// @param f The transform function or functor. Must satisfy the `is_transform_like` concept.
    /// @param c The concurrency level for this node.
    /// @return An object for connecting this node to others in the graph.
    auto transform(std::string name, is_transform_like auto f, concurrency c = concurrency::serial)
    {
      return create_glue().transform(std::move(name), std::move(f), c);
    }

    /// @brief Adds an unfold algorithm to the graph.
    ///
    /// @tparam Splitter The type of the splitter for the unfold operation.
    /// @param name The name of the unfold node.
    /// @param pred The predicate to select data for unfolding. Must satisfy `is_predicate_like`.
    /// @param unf The unfold function or functor.
    /// @param c The concurrency level for this node.
    /// @return An object for connecting this node to others in the graph.
    template <typename Splitter>
    auto unfold(std::string name,
                is_predicate_like auto pred,
                auto unf,
                concurrency c = concurrency::serial)
    {
      return create_glue(false).unfold(std::move(name), std::move(pred), std::move(unf), c);
    }

    /// @brief Adds an unfold algorithm to the graph (with an auto-generated name).
    ///
    /// @tparam Splitter The type of the splitter for the unfold operation.
    /// @param pred The predicate to select data for unfolding. Must satisfy `is_predicate_like`.
    /// @param unf The unfold function or functor.
    /// @param c The concurrency level for this node.
    /// @return An object for connecting this node to others in the graph.
    template <typename Splitter>
    auto unfold(is_predicate_like auto pred, auto unf, concurrency c = concurrency::serial)
    {
      return create_glue(false).unfold(std::move(pred), std::move(unf), c);
    }

    /// @brief Adds an output node to the graph.
    ///
    /// @param name The name of the output node.
    /// @param f The output function or functor. Must satisfy the `is_output_like` concept.
    /// @param c The concurrency level for this node.
    /// @return An object for connecting this node to others in the graph.
    auto output(std::string name, is_output_like auto f, concurrency c = concurrency::serial)
    {
      return create_glue().output(std::move(name), std::move(f), c);
    }

  private:
    graph_proxy(configuration const* config,
                tbb::flow::graph& g,
                node_catalog& nodes,
                std::shared_ptr<T> bound_obj,
                std::vector<std::string>& errors)
      requires(not std::same_as<T, void_tag>)
      : config_{config}, graph_{g}, nodes_{nodes}, bound_obj_{bound_obj}, errors_{errors}
    {
    }

    glue<T> create_glue(bool use_bound_object = true)
    {
      return glue{graph_, nodes_, (use_bound_object ? bound_obj_ : nullptr), errors_, config_};
    }

    configuration const* config_;
    tbb::flow::graph& graph_;
    node_catalog& nodes_;
    std::shared_ptr<T> bound_obj_;
    std::vector<std::string>& errors_;
  };
}

#endif // PHLEX_CORE_GRAPH_PROXY_HPP
