#pragma once

#ifdef SIGNALS_EXPORTS
#define SIGNALS_API __declspec(dllexport)
#else
#define SIGNALS_API __declspec(dllimport)
#endif

// A wrapper for all signals data. This allows data to be numpy or mxArrays, etc.
class SIGNALS_API DataContainer {
public:
    virtual ~DataContainer() = default;

    // Virtual interface for data access
    virtual size_t size() const = 0;
    virtual void* get_data() = 0;
    virtual const void* get_data() const = 0;

    // Optionally, add type info or scalar/array info
    virtual bool is_scalar() const { return true; }
};


template<typename T>
class SIGNALS_API TypedDataContainer : public DataContainer {
public:
    TypedDataContainer(size_t size) : data_(size) {}

    T* data() { return data_.data(); }
    const T* data() const { return data_.data(); }

private:
    std::shared_ptr<T> data_;
};

// Usage
//DataContainer* container = new TypedDataContainer<float>(10);
//float* float_data = container->get_data_as<float>();
//if (float_data) {
//    // Safe to use float_data
//}

//#include <memory>
//
//class NumpyArrayWrapper {
//public:
//    NumpyArrayWrapper(PyArrayObject* arr)
//        : array_(arr, [](PyArrayObject* p) { /* custom deleter if needed */ }) {}
//
//    PyArrayObject* get() const { return array_.get(); }
//
//private:
//    std::shared_ptr<PyArrayObject> array_;
//};
//// Similar for MEX arrays